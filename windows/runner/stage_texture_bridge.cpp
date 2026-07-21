#include "stage_texture_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_texture_registrar.h>
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <iterator>
#include <memory>
#include <mutex>
#include <string>
#include <variant>

namespace {

using ShowHostHandle = void*;
using ShowHostStageTextureSource = void*;
using FrameAvailableCallback = void (*)(void*);

struct ShowHostStageTextureFrame {
  uintptr_t shared_handle;
  uintptr_t lease_token;
  uint32_t width;
  uint32_t height;
  uint64_t generation;
  uint64_t frame_id;
};

using CreateSource = ShowHostStageTextureSource (*)(ShowHostHandle);
using DestroySource = void (*)(ShowHostStageTextureSource);
using SetSourceActive = void (*)(ShowHostStageTextureSource, bool);
using SetFrameCallback = void (*)(ShowHostStageTextureSource,
                                  FrameAvailableCallback,
                                  void*);
using SetStageDevice = bool (*)(ShowHostHandle, uintptr_t);
using AcquireFrame = bool (*)(ShowHostStageTextureSource,
                              ShowHostStageTextureFrame*);
using ReleaseFrame = void (*)(uintptr_t);

struct ShowTextureApi {
  HMODULE module{};
  CreateSource create_source{};
  DestroySource destroy_source{};
  SetSourceActive set_active{};
  SetFrameCallback set_callback{};
  SetStageDevice set_stage_device{};
  AcquireFrame acquire{};
  ReleaseFrame release{};

  bool Load() {
    module = GetModuleHandleW(L"libshow_host.dll");
    if (!module) {
      module = LoadLibraryW(L"libshow_host.dll");
    }
    if (!module) {
      return false;
    }
    create_source = reinterpret_cast<CreateSource>(
        GetProcAddress(module, "show_host_create_stage_texture_source"));
    destroy_source = reinterpret_cast<DestroySource>(
        GetProcAddress(module, "show_host_destroy_stage_texture_source"));
    set_active = reinterpret_cast<SetSourceActive>(
        GetProcAddress(module, "show_host_stage_texture_source_set_active"));
    set_callback = reinterpret_cast<SetFrameCallback>(GetProcAddress(
        module, "show_host_stage_texture_source_set_frame_callback"));
    set_stage_device = reinterpret_cast<SetStageDevice>(
        GetProcAddress(module, "show_host_set_stage_d3d_device"));
    acquire = reinterpret_cast<AcquireFrame>(
        GetProcAddress(module, "show_host_stage_texture_source_acquire"));
    release = reinterpret_cast<ReleaseFrame>(
        GetProcAddress(module, "show_host_release_stage_texture_frame"));
    return create_source && destroy_source && set_active && set_callback &&
           set_stage_device && acquire && release;
  }
};

int64_t ReadInt64(const flutter::EncodableValue* value,
                  const std::string& key) {
  if (!value) {
    return 0;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(value);
  if (!map) {
    return 0;
  }
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) {
    return 0;
  }
  if (const auto* number = std::get_if<int64_t>(&found->second)) {
    return *number;
  }
  if (const auto* number = std::get_if<int32_t>(&found->second)) {
    return *number;
  }
  return 0;
}

bool ReadBool(const flutter::EncodableValue* value,
              const std::string& key,
              bool fallback) {
  if (!value) {
    return fallback;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(value);
  if (!map) {
    return fallback;
  }
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) {
    return fallback;
  }
  if (const auto* boolean = std::get_if<bool>(&found->second)) {
    return *boolean;
  }
  return fallback;
}

}  // namespace

struct StageTextureBridge::Impl {
  explicit Impl(flutter::FlutterEngine* flutter_engine)
      : engine(flutter_engine),
        registrar(flutter_engine
                      ? FlutterDesktopRegistrarGetTextureRegistrar(
                            flutter_engine->GetRegistrarForPlugin(
                                "kirakara_stage_texture"))
                      : nullptr) {
    RegisterChannel();
  }

  ~Impl() {
    BeginShutdown();
    ReleaseCurrentFrame();
    DestroySource();
    channel.reset();
  }

  void RegisterChannel() {
    if (!engine) {
      return;
    }
    channel = std::make_unique<
        flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(), "kirakara/stage_texture",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<
                   flutter::MethodResult<flutter::EncodableValue>> result) {
          if (call.method_name() == "attach") {
            const auto host_address = ReadInt64(
                call.arguments(), "hostHandle");
            const auto id = Attach(reinterpret_cast<ShowHostHandle>(
                static_cast<intptr_t>(host_address)));
            if (id < 0) {
              result->Error("stage_texture_unavailable",
                            "Unable to attach the Unified Stage texture");
            } else {
              result->Success(flutter::EncodableValue(id));
            }
            return;
          }
          if (call.method_name() == "setActive") {
            const bool active = ReadBool(
                call.arguments(), "active", false);
            SetActive(active);
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == "isSupported") {
            result->Success(flutter::EncodableValue(EnsureApi()));
            return;
          }
          if (call.method_name() == "getStats") {
            flutter::EncodableMap stats;
            stats[flutter::EncodableValue("publishedFrames")] =
                flutter::EncodableValue(static_cast<int64_t>(
                    published_frames.load(std::memory_order_relaxed)));
            stats[flutter::EncodableValue("acquiredFrames")] =
                flutter::EncodableValue(static_cast<int64_t>(
                    acquired_frames.load(std::memory_order_relaxed)));
            result->Success(flutter::EncodableValue(std::move(stats)));
            return;
          }
          result->NotImplemented();
        });
  }

  bool EnsureApi() {
    std::lock_guard lock(state_mutex);
    if (api_loaded) {
      return api_available;
    }
    api_loaded = true;
    api_available = api.Load();
    return api_available;
  }

  bool EnsureStageDevice() {
    if (stage_device && SUCCEEDED(stage_device->GetDeviceRemovedReason())) {
      return true;
    }
    stage_device.Reset();
    if (!engine) {
      return false;
    }

    IDXGIAdapter* raw_adapter = nullptr;
    if (!engine->GetGraphicsAdapter(&raw_adapter) || !raw_adapter) {
      return false;
    }
    Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
    adapter.Attach(raw_adapter);

    constexpr D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };
    D3D_FEATURE_LEVEL selected{};
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
    constexpr UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT |
                           D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    const auto result = D3D11CreateDevice(
        adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, flags, levels,
        static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION,
        stage_device.GetAddressOf(), &selected, context.GetAddressOf());
    return SUCCEEDED(result) && stage_device;
  }

  int64_t Attach(ShowHostHandle host) {
    if (!host || !registrar || shutting_down.load()) {
      return -1;
    }
    if (!EnsureApi()) {
      return -1;
    }

    std::lock_guard lock(state_mutex);
    const auto existing_texture_id = texture_id.load();
    if (source && attached_host == host && existing_texture_id >= 0) {
      api.set_active(source, true);
      active.store(true);
      FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
          registrar, existing_texture_id);
      return existing_texture_id;
    }
    if (source) {
      api.set_callback(source, nullptr, nullptr);
      api.set_active(source, false);
      api.destroy_source(source);
      source = nullptr;
      attached_host = nullptr;
      ReleaseCurrentFrameLocked();
    }

    if (!EnsureStageDevice() || !api.set_stage_device(
            host, reinterpret_cast<uintptr_t>(stage_device.Get()))) {
      return -1;
    }

    source = api.create_source(host);
    if (!source) {
      return -1;
    }
    attached_host = host;

    auto registered_texture_id = texture_id.load();
    if (registered_texture_id < 0) {
      FlutterDesktopTextureInfo texture_info{};
      texture_info.type = kFlutterDesktopGpuSurfaceTexture;
      texture_info.gpu_surface_config.struct_size =
          sizeof(FlutterDesktopGpuSurfaceTextureConfig);
      texture_info.gpu_surface_config.type =
          kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
      texture_info.gpu_surface_config.user_data = this;
      texture_info.gpu_surface_config.callback =
          [](size_t width, size_t height, void* context)
              -> const FlutterDesktopGpuSurfaceDescriptor* {
            return static_cast<Impl*>(context)->ObtainDescriptor(
                width, height);
          };
      registered_texture_id =
          FlutterDesktopTextureRegistrarRegisterExternalTexture(
          registrar, &texture_info);
      if (registered_texture_id < 0) {
        api.destroy_source(source);
        source = nullptr;
        attached_host = nullptr;
        return -1;
      }
      texture_id.store(registered_texture_id);
    }

    active.store(true);
    api.set_active(source, true);
    api.set_callback(source, &FrameAvailable, this);
    FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
        registrar, registered_texture_id);
    return registered_texture_id;
  }

  void SetActive(bool value) {
    std::lock_guard lock(state_mutex);
    if (!source || shutting_down.load()) {
      active.store(false);
      return;
    }
    active.store(value);
    api.set_active(source, value);
    const auto registered_texture_id = texture_id.load();
    if (value && registered_texture_id >= 0) {
      FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
          registrar, registered_texture_id);
    }
  }

  static void FrameAvailable(void* context) {
    auto* self = static_cast<Impl*>(context);
    if (!self || !self->active.load() || self->shutting_down.load() ||
        !self->registrar || self->texture_id.load() < 0) {
      return;
    }
    self->published_frames.fetch_add(1, std::memory_order_relaxed);
    FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
        self->registrar, self->texture_id.load());
  }

  struct DeferredLeaseRelease {
    ReleaseFrame release{};
    uintptr_t token{};
  };

  static void ReleaseDeferredLease(void* context) {
    std::unique_ptr<DeferredLeaseRelease> deferred(
        static_cast<DeferredLeaseRelease*>(context));
    if (deferred && deferred->release && deferred->token) {
      deferred->release(deferred->token);
    }
  }

  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(
      size_t,
      size_t) {
    std::lock_guard lock(state_mutex);
    if (!source || !active.load() || shutting_down.load()) {
      return nullptr;
    }

    ShowHostStageTextureFrame next{};
    if (!api.acquire(source, &next)) {
      if (!descriptor.handle) {
        return nullptr;
      }
      descriptor.release_callback = nullptr;
      descriptor.release_context = nullptr;
      return &descriptor;
    }
    acquired_frames.fetch_add(1, std::memory_order_relaxed);

    descriptor = {};
    descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    descriptor.handle = reinterpret_cast<void*>(next.shared_handle);
    descriptor.width = descriptor.visible_width = next.width;
    descriptor.height = descriptor.visible_height = next.height;
    descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
    if (next.lease_token) {
      auto deferred = std::make_unique<DeferredLeaseRelease>();
      deferred->release = api.release;
      deferred->token = next.lease_token;
      descriptor.release_callback = &ReleaseDeferredLease;
      descriptor.release_context = deferred.release();
    }
    return &descriptor;
  }

  void BeginShutdown() {
    if (shutting_down.exchange(true)) {
      return;
    }
    active.store(false);
    std::lock_guard lock(state_mutex);
    if (source && api_available) {
      api.set_callback(source, nullptr, nullptr);
      api.set_active(source, false);
    }
    const auto registered_texture_id = texture_id.load();
    if (registrar && registered_texture_id >= 0) {
      FlutterDesktopTextureRegistrarUnregisterExternalTexture(
          registrar, registered_texture_id, nullptr, nullptr);
      texture_id.store(-1);
    }
  }

  void ReleaseCurrentFrameLocked() {
    descriptor = {};
  }

  void ReleaseCurrentFrame() {
    std::lock_guard lock(state_mutex);
    ReleaseCurrentFrameLocked();
  }

  void DestroySource() {
    std::lock_guard lock(state_mutex);
    if (source && api_available) {
      api.destroy_source(source);
    }
    source = nullptr;
    attached_host = nullptr;
  }

  flutter::FlutterEngine* engine{};
  FlutterDesktopTextureRegistrarRef registrar{};
  std::unique_ptr<
      flutter::MethodChannel<flutter::EncodableValue>> channel;
  ShowTextureApi api;
  bool api_loaded{};
  bool api_available{};
  ShowHostHandle attached_host{};
  ShowHostStageTextureSource source{};
  std::atomic_int64_t texture_id{-1};
  Microsoft::WRL::ComPtr<ID3D11Device> stage_device;
  std::atomic_bool active{};
  std::atomic_bool shutting_down{};
  std::atomic_uint64_t published_frames{};
  std::atomic_uint64_t acquired_frames{};
  std::mutex state_mutex;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
};

StageTextureBridge::StageTextureBridge(flutter::FlutterEngine* engine)
    : impl_(std::make_unique<Impl>(engine)) {}

StageTextureBridge::~StageTextureBridge() = default;

void StageTextureBridge::BeginShutdown() {
  if (impl_) {
    impl_->BeginShutdown();
  }
}
