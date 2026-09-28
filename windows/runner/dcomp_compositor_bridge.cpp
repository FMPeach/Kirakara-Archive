#include "dcomp_compositor_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <optional>
#include <sstream>
#include <utility>
#include <vector>

#include "kirakara_flutter_compositor_api.h"

namespace {

using EncodableValue = flutter::EncodableValue;
using MethodCall = flutter::MethodCall<EncodableValue>;
using MethodResult = flutter::MethodResult<EncodableValue>;

constexpr wchar_t kBackendEnvironment[] = L"KIRAKARA_COMPOSITOR_BACKEND";
constexpr wchar_t kTestModeEnvironment[] = L"KIRAKARA_COMPOSITOR_TEST_MODE";
constexpr char kChannelName[] = "kirakara/dcomp_compositor";

std::string ReadBackendEnvironment() {
  const DWORD required =
      ::GetEnvironmentVariableW(kBackendEnvironment, nullptr, 0);
  if (required == 0) {
    return {};
  }

  std::wstring wide(required, L'\0');
  const DWORD written = ::GetEnvironmentVariableW(
      kBackendEnvironment, wide.data(), static_cast<DWORD>(wide.size()));
  if (written == 0 || written >= wide.size()) {
    return {};
  }
  wide.resize(written);

  const int utf8_size = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, wide.data(), static_cast<int>(wide.size()),
      nullptr, 0, nullptr, nullptr);
  if (utf8_size <= 0) {
    return {};
  }
  std::string value(utf8_size, '\0');
  ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide.data(),
                        static_cast<int>(wide.size()), value.data(), utf8_size,
                        nullptr, nullptr);
  std::transform(
      value.begin(), value.end(), value.begin(),
      [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size =
      ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return L"The compositor returned an error that could not be decoded.";
  }
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), size);
  return result;
}

bool SyntheticTestModeEnabled() {
  wchar_t value[2]{};
  return ::GetEnvironmentVariableW(kTestModeEnvironment, value,
                                   static_cast<DWORD>(std::size(value))) == 1 &&
         value[0] == L'1';
}

struct TopLevelWindowCounts {
  uint32_t total = 0;
  uint32_t visible = 0;
};

struct TestResizeDelta {
  int32_t width = 0;
  int32_t height = 0;
};

TopLevelWindowCounts CountCurrentProcessTopLevelWindows() {
  struct CountContext {
    DWORD process_id;
    TopLevelWindowCounts counts;
  } context{::GetCurrentProcessId(), {}};
  ::EnumWindows(
      [](HWND window, LPARAM parameter) -> BOOL {
        auto* context = reinterpret_cast<CountContext*>(parameter);
        DWORD process_id = 0;
        ::GetWindowThreadProcessId(window, &process_id);
        if (process_id == context->process_id) {
          ++context->counts.total;
          if (::IsWindowVisible(window)) {
            ++context->counts.visible;
          }
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&context));
  return context.counts;
}

struct MonitorRecord {
  HMONITOR handle = nullptr;
  RECT bounds{};
  RECT work_area{};
  bool primary = false;
  UINT dpi = 0;
};

std::vector<MonitorRecord> EnumerateMonitors() {
  std::vector<MonitorRecord> monitors;
  ::EnumDisplayMonitors(
      nullptr, nullptr,
      [](HMONITOR monitor, HDC, LPRECT, LPARAM parameter) -> BOOL {
        auto* values = reinterpret_cast<std::vector<MonitorRecord>*>(parameter);
        MONITORINFO info{};
        info.cbSize = sizeof(info);
        if (!::GetMonitorInfoW(monitor, &info)) {
          return TRUE;
        }
        values->push_back(MonitorRecord{
            monitor,
            info.rcMonitor,
            info.rcWork,
            (info.dwFlags & MONITORINFOF_PRIMARY) != 0,
            FlutterDesktopGetDpiForMonitor(monitor),
        });
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&monitors));
  return monitors;
}

flutter::EncodableList MonitorValues(
    const std::vector<MonitorRecord>& monitors) {
  flutter::EncodableList values;
  for (size_t index = 0; index < monitors.size(); ++index) {
    const auto& monitor = monitors[index];
    values.emplace_back(flutter::EncodableMap{
        {EncodableValue("index"),
         EncodableValue(static_cast<int32_t>(index))},
        {EncodableValue("primary"), EncodableValue(monitor.primary)},
        {EncodableValue("left"), EncodableValue(monitor.bounds.left)},
        {EncodableValue("top"), EncodableValue(monitor.bounds.top)},
        {EncodableValue("right"), EncodableValue(monitor.bounds.right)},
        {EncodableValue("bottom"), EncodableValue(monitor.bounds.bottom)},
        {EncodableValue("dpi"),
         EncodableValue(static_cast<int32_t>(monitor.dpi))},
        {EncodableValue("scalePercent"),
         EncodableValue(static_cast<int32_t>(
             (static_cast<uint64_t>(monitor.dpi) * 100u + 48u) / 96u))},
    });
  }
  return values;
}

std::optional<int32_t> ReadTestMonitorIndex(
    const EncodableValue* arguments) {
  if (!arguments) {
    return std::nullopt;
  }
  int64_t index = -1;
  if (const auto* int32_value = std::get_if<int32_t>(arguments)) {
    index = *int32_value;
  } else if (const auto* int64_value = std::get_if<int64_t>(arguments)) {
    index = *int64_value;
  } else {
    return std::nullopt;
  }
  if (index < 0 || index > 63) {
    return std::nullopt;
  }
  return static_cast<int32_t>(index);
}

std::optional<uint32_t> ReadTestStallDuration(const EncodableValue* arguments) {
  if (!arguments) {
    return std::nullopt;
  }
  int64_t duration = 0;
  if (const auto* int32_value = std::get_if<int32_t>(arguments)) {
    duration = *int32_value;
  } else if (const auto* int64_value = std::get_if<int64_t>(arguments)) {
    duration = *int64_value;
  } else {
    return std::nullopt;
  }
  if (duration < 1 || duration > 2000) {
    return std::nullopt;
  }
  return static_cast<uint32_t>(duration);
}

std::optional<TestResizeDelta> ReadTestResizeDelta(
    const EncodableValue* arguments) {
  const auto* map = arguments ? std::get_if<flutter::EncodableMap>(arguments)
                              : nullptr;
  if (!map) {
    return std::nullopt;
  }
  auto read_delta = [map](const char* key) -> std::optional<int32_t> {
    const auto found = map->find(EncodableValue(std::string(key)));
    if (found == map->end()) {
      return std::nullopt;
    }
    int64_t value = 0;
    if (const auto* int32_value = std::get_if<int32_t>(&found->second)) {
      value = *int32_value;
    } else if (const auto* int64_value =
                   std::get_if<int64_t>(&found->second)) {
      value = *int64_value;
    } else {
      return std::nullopt;
    }
    if (value < -512 || value > 512) {
      return std::nullopt;
    }
    return static_cast<int32_t>(value);
  };

  const auto width = read_delta("widthDelta");
  const auto height = read_delta("heightDelta");
  if (!width || !height || (*width == 0 && *height == 0)) {
    return std::nullopt;
  }
  return TestResizeDelta{*width, *height};
}

std::string ResultName(int32_t result) {
  switch (result) {
    case kKirakaraFlutterCompositorSuccess:
      return "success";
    case kKirakaraFlutterCompositorInvalidArgument:
      return "invalid_argument";
    case kKirakaraFlutterCompositorVersionMismatch:
      return "version_mismatch";
    case kKirakaraFlutterCompositorBusy:
      return "busy";
    case kKirakaraFlutterCompositorUnavailable:
      return "unavailable";
    case kKirakaraFlutterCompositorViewNotConfigured:
      return "view_not_configured";
    default:
      return "unknown(" + std::to_string(result) + ")";
  }
}

std::string HexHresult(int32_t value) {
  std::ostringstream stream;
  stream << "0x" << std::hex << std::uppercase << static_cast<uint32_t>(value);
  return stream.str();
}

EncodableValue DiagnosticsValue(
    const KirakaraFlutterCompositorDiagnostics& diagnostics) {
  return EncodableValue(flutter::EncodableMap{
      {EncodableValue("active"), EncodableValue(diagnostics.active != 0)},
      {EncodableValue("abiVersion"),
       EncodableValue(static_cast<int32_t>(diagnostics.abi_version))},
      {EncodableValue("patchsetVersion"),
       EncodableValue(static_cast<int32_t>(diagnostics.patchset_version))},
      {EncodableValue("capabilities"),
       EncodableValue(static_cast<int64_t>(diagnostics.capabilities))},
      {EncodableValue("topLevelWindow"),
       EncodableValue(static_cast<int64_t>(diagnostics.top_level_window))},
      {EncodableValue("width"),
       EncodableValue(static_cast<int32_t>(diagnostics.width))},
      {EncodableValue("height"),
       EncodableValue(static_cast<int32_t>(diagnostics.height))},
      {EncodableValue("initializationHresult"),
       EncodableValue(diagnostics.initialization_hresult)},
      {EncodableValue("lastStagePresentHresult"),
       EncodableValue(diagnostics.last_stage_present_hresult)},
      {EncodableValue("lastStagePacingStatus"),
       EncodableValue(diagnostics.last_stage_pacing_status)},
      {EncodableValue("lastResizeHresult"),
       EncodableValue(diagnostics.last_resize_hresult)},
      {EncodableValue("flutterPresentCount"),
       EncodableValue(static_cast<int64_t>(diagnostics.flutter_present_count))},
      {EncodableValue("stagePresentCount"),
       EncodableValue(static_cast<int64_t>(diagnostics.stage_present_count))},
      {EncodableValue("stageWaitWakeCount"),
       EncodableValue(static_cast<int64_t>(diagnostics.stage_wait_wake_count))},
      {EncodableValue("stageDeviceRemovedCount"),
       EncodableValue(
           static_cast<int64_t>(diagnostics.stage_device_removed_count))},
      {EncodableValue("stageOccludedCount"),
       EncodableValue(static_cast<int64_t>(diagnostics.stage_occluded_count))},
      {EncodableValue("surfaceResizeCount"),
       EncodableValue(static_cast<int64_t>(diagnostics.surface_resize_count))},
      {EncodableValue("compositionTreeCommitCount"),
       EncodableValue(static_cast<int64_t>(
           diagnostics.composition_tree_commit_count))},
  });
}

}  // namespace

struct DcompCompositorBridge::Impl {
  bool ResolveApi(std::string* error) {
    const HMODULE engine_module = ::GetModuleHandleW(L"flutter_windows.dll");
    if (!engine_module) {
      *error =
          "KIRAKARA_COMPOSITOR_BACKEND=synthetic was requested, but "
          "flutter_windows.dll is not loaded.";
      return false;
    }

    const auto get_api =
        reinterpret_cast<FlutterDesktopKirakaraCompositorGetApiProc>(
            ::GetProcAddress(engine_module,
                             KIRAKARA_FLUTTER_COMPOSITOR_EXPORT_NAME));
    if (!get_api) {
      *error =
          "KIRAKARA_COMPOSITOR_BACKEND=synthetic requires the Kirakara "
          "patched Flutter Engine, but its versioned API export is "
          "missing. The selected DLL is likely the stock Engine.";
      return false;
    }

    api = {};
    api.struct_size = sizeof(api);
    const int32_t result =
        get_api(KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION, &api);
    if (result != kKirakaraFlutterCompositorSuccess) {
      *error = "The Kirakara Flutter Engine rejected compositor ABI " +
               std::to_string(KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION) + ": " +
               ResultName(result) + ".";
      return false;
    }

    if (api.struct_size != sizeof(api) ||
        api.abi_version != KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION ||
        api.patchset_version != KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_VERSION ||
        !api.patchset_revision || !api.engine_revision ||
        std::strcmp(api.patchset_revision,
                    KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_REVISION) != 0 ||
        std::strcmp(api.engine_revision,
                    KIRAKARA_FLUTTER_COMPOSITOR_ENGINE_REVISION) != 0 ||
        !api.prepare_next_view || !api.cancel_prepared_view ||
        !api.get_view_diagnostics) {
      std::ostringstream stream;
      stream << "Kirakara Flutter Engine metadata mismatch. Expected ABI "
             << KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION << ", patchset "
             << KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_VERSION << " ("
             << KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_REVISION << "), engine "
             << KIRAKARA_FLUTTER_COMPOSITOR_ENGINE_REVISION << ". Got ABI "
             << api.abi_version << ", patchset " << api.patchset_version << " ("
             << (api.patchset_revision ? api.patchset_revision : "null")
             << "), engine "
             << (api.engine_revision ? api.engine_revision : "null") << ".";
      *error = stream.str();
      return false;
    }
    return true;
  }

  bool Prepare(HWND top_level_window, std::string* error) {
    KirakaraFlutterCompositorConfig config{};
    config.struct_size = sizeof(config);
    config.abi_version = KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION;
    config.patchset_version = KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_VERSION;
    config.flags = kKirakaraFlutterCompositorSyntheticStage |
                   kKirakaraFlutterCompositorRequireComposition;
    config.top_level_window = reinterpret_cast<uintptr_t>(top_level_window);

    const int32_t result = api.prepare_next_view(&config);
    if (result != kKirakaraFlutterCompositorSuccess) {
      *error =
          "The Kirakara Flutter Engine could not prepare the synthetic "
          "DirectComposition view: " +
          ResultName(result) + ".";
      return false;
    }
    window = top_level_window;
    prepared = true;
    return true;
  }

  bool Attach(flutter::FlutterEngine* engine, std::string* error) {
    prepared = false;
    if (!engine) {
      *error = "The synthetic DirectComposition view has no Flutter Engine.";
      return false;
    }
    const FlutterDesktopPluginRegistrarRef registrar =
        engine->GetRegistrarForPlugin("kirakara_dcomp_compositor");
    view =
        registrar ? FlutterDesktopPluginRegistrarGetView(registrar) : nullptr;
    if (!view) {
      *error = "The synthetic DirectComposition view reference is unavailable.";
      return false;
    }

    KirakaraFlutterCompositorDiagnostics diagnostics{};
    if (!ReadDiagnostics(&diagnostics, error)) {
      return false;
    }
    constexpr uint64_t kRequiredCapabilities =
        kKirakaraFlutterCompositorDirectComposition |
        kKirakaraFlutterCompositorPremultipliedAlpha |
        kKirakaraFlutterCompositorSyntheticStageProducer |
        kKirakaraFlutterCompositorIndependentStageProducer |
        kKirakaraFlutterCompositorCompositorClockPacing |
        kKirakaraFlutterCompositorInPlaceResize;
    if (!diagnostics.active ||
        (diagnostics.capabilities & kRequiredCapabilities) !=
            kRequiredCapabilities) {
      *error =
          "The patched Engine created a view, but the required synthetic "
          "DirectComposition capabilities are not active (init HRESULT " +
          HexHresult(diagnostics.initialization_hresult) + ").";
      return false;
    }

    channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        engine->messenger(), kChannelName,
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const MethodCall& call,
                                         std::unique_ptr<MethodResult> result) {
      if (call.method_name() == "getDiagnostics") {
        KirakaraFlutterCompositorDiagnostics diagnostics{};
        std::string error;
        if (!ReadDiagnostics(&diagnostics, &error)) {
          result->Error("dcomp_diagnostics_unavailable", error);
          return;
        }
        result->Success(DiagnosticsValue(diagnostics));
        return;
      }
      if (call.method_name() == "getBackendInfo") {
        const auto top_level_windows = CountCurrentProcessTopLevelWindows();
        const auto monitor_records = EnumerateMonitors();
        const auto monitors = MonitorValues(monitor_records);
        const HMONITOR current_monitor =
            ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
        int32_t current_monitor_index = -1;
        for (size_t index = 0; index < monitor_records.size(); ++index) {
          if (monitor_records[index].handle == current_monitor) {
            current_monitor_index = static_cast<int32_t>(index);
            break;
          }
        }
        const UINT window_dpi = FlutterDesktopGetDpiForHWND(window);
        const DPI_AWARENESS_CONTEXT window_dpi_context =
            ::GetWindowDpiAwarenessContext(window);
        const DPI_AWARENESS window_dpi_awareness =
            ::GetAwarenessFromDpiAwarenessContext(window_dpi_context);
        const bool window_is_per_monitor_v2 =
            ::AreDpiAwarenessContextsEqual(
                window_dpi_context,
                DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != FALSE;
        result->Success(EncodableValue(flutter::EncodableMap{
            {EncodableValue("backend"), EncodableValue("synthetic")},
            {EncodableValue("abiVersion"),
             EncodableValue(static_cast<int32_t>(api.abi_version))},
            {EncodableValue("patchsetVersion"),
             EncodableValue(static_cast<int32_t>(api.patchset_version))},
            {EncodableValue("patchsetRevision"),
             EncodableValue(std::string(api.patchset_revision))},
            {EncodableValue("engineRevision"),
             EncodableValue(std::string(api.engine_revision))},
            {EncodableValue("processTopLevelWindowCount"),
             EncodableValue(static_cast<int32_t>(top_level_windows.total))},
            {EncodableValue("visibleTopLevelWindowCount"),
             EncodableValue(static_cast<int32_t>(top_level_windows.visible))},
            {EncodableValue("topLevelWindow"),
             EncodableValue(static_cast<int64_t>(
                 reinterpret_cast<uintptr_t>(window)))},
            {EncodableValue("windowDpi"),
             EncodableValue(static_cast<int32_t>(window_dpi))},
            {EncodableValue("windowScalePercent"),
             EncodableValue(static_cast<int32_t>(
                 (static_cast<uint64_t>(window_dpi) * 100u + 48u) / 96u))},
            {EncodableValue("windowDpiAwareness"),
             EncodableValue(static_cast<int32_t>(window_dpi_awareness))},
            {EncodableValue("windowIsPerMonitorV2"),
             EncodableValue(window_is_per_monitor_v2)},
            {EncodableValue("monitorCount"),
             EncodableValue(static_cast<int32_t>(monitors.size()))},
            {EncodableValue("currentMonitorIndex"),
             EncodableValue(current_monitor_index)},
            {EncodableValue("monitors"), EncodableValue(monitors)},
        }));
        return;
      }
      if (call.method_name() == "stallPlatformThreadForTest") {
        if (!SyntheticTestModeEnabled()) {
          result->Error(
              "dcomp_test_mode_disabled",
              "Set KIRAKARA_COMPOSITOR_TEST_MODE=1 to use the bounded "
              "platform-thread stall probe.");
          return;
        }
        const auto duration = ReadTestStallDuration(call.arguments());
        if (!duration) {
          result->Error("dcomp_invalid_test_duration",
                        "The test stall must be 1 to 2000 milliseconds.");
          return;
        }
        KirakaraFlutterCompositorDiagnostics before{};
        KirakaraFlutterCompositorDiagnostics after{};
        std::string error;
        if (!ReadDiagnostics(&before, &error)) {
          result->Error("dcomp_diagnostics_unavailable", error);
          return;
        }
        // This is reachable only in explicit compositor test mode. It
        // deliberately blocks the Flutter platform thread once so the
        // independent Stage producer can be measured during the stall.
        ::Sleep(*duration);
        if (!ReadDiagnostics(&after, &error)) {
          result->Error("dcomp_diagnostics_unavailable", error);
          return;
        }
        result->Success(EncodableValue(flutter::EncodableMap{
            {EncodableValue("durationMilliseconds"),
             EncodableValue(static_cast<int32_t>(*duration))},
            {EncodableValue("stagePresentDelta"),
             EncodableValue(static_cast<int64_t>(after.stage_present_count -
                                                 before.stage_present_count))},
            {EncodableValue("stageWaitWakeDelta"),
             EncodableValue(static_cast<int64_t>(
                 after.stage_wait_wake_count - before.stage_wait_wake_count))},
            {EncodableValue("flutterPresentDelta"),
             EncodableValue(static_cast<int64_t>(
                 after.flutter_present_count - before.flutter_present_count))},
            {EncodableValue("before"), DiagnosticsValue(before)},
            {EncodableValue("after"), DiagnosticsValue(after)},
        }));
        return;
      }
      if (call.method_name() == "resizeWindowByForTest") {
        if (!SyntheticTestModeEnabled()) {
          result->Error(
              "dcomp_test_mode_disabled",
              "Set KIRAKARA_COMPOSITOR_TEST_MODE=1 to resize the probe "
              "window.");
          return;
        }
        const auto delta = ReadTestResizeDelta(call.arguments());
        if (!delta) {
          result->Error("dcomp_invalid_test_resize",
                        "Test resize deltas must be -512 to 512 logical "
                        "pixels and cannot both be zero.");
          return;
        }
        if (!window || !::IsWindow(window) ||
            !::PostMessageW(
                window, kKirakaraCompositorResizeForTestMessage,
                static_cast<WPARAM>(static_cast<intptr_t>(delta->width)),
                static_cast<LPARAM>(static_cast<intptr_t>(delta->height)))) {
          result->Error("dcomp_test_resize_unavailable",
                        "Could not queue the synthetic compositor resize.");
          return;
        }
        result->Success();
        return;
      }
      if (call.method_name() == "moveWindowToMonitorForTest") {
        if (!SyntheticTestModeEnabled()) {
          result->Error(
              "dcomp_test_mode_disabled",
              "Set KIRAKARA_COMPOSITOR_TEST_MODE=1 to move the probe "
              "window between monitors.");
          return;
        }
        const auto monitor_index = ReadTestMonitorIndex(call.arguments());
        const auto monitors = EnumerateMonitors();
        if (!monitor_index ||
            static_cast<size_t>(*monitor_index) >= monitors.size()) {
          result->Error("dcomp_invalid_test_monitor",
                        "The requested test monitor index is unavailable.");
          return;
        }
        if (!window || !::IsWindow(window) ||
            !::PostMessageW(
                window, kKirakaraCompositorMoveToMonitorForTestMessage,
                static_cast<WPARAM>(*monitor_index), 0)) {
          result->Error("dcomp_test_monitor_move_unavailable",
                        "Could not queue the synthetic compositor monitor "
                        "move.");
          return;
        }
        result->Success();
        return;
      }
      if (call.method_name() == "closeWindowForTest") {
        if (!SyntheticTestModeEnabled()) {
          result->Error(
              "dcomp_test_mode_disabled",
              "Set KIRAKARA_COMPOSITOR_TEST_MODE=1 to close the probe window.");
          return;
        }
        if (!window || !::IsWindow(window)) {
          result->Error("dcomp_test_window_unavailable",
                        "The synthetic compositor test window is unavailable.");
          return;
        }
        result->Success();
        ::PostMessageW(window, WM_CLOSE, 0, 0);
        return;
      }
      result->NotImplemented();
    });
    return true;
  }

  bool ReadDiagnostics(KirakaraFlutterCompositorDiagnostics* diagnostics,
                       std::string* error) const {
    *diagnostics = {};
    diagnostics->struct_size = sizeof(*diagnostics);
    diagnostics->abi_version = KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION;
    diagnostics->patchset_version =
        KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_VERSION;
    const int32_t result = api.get_view_diagnostics(
        reinterpret_cast<uintptr_t>(view), diagnostics);
    if (result != kKirakaraFlutterCompositorSuccess) {
      *error =
          "Kirakara compositor diagnostics failed: " + ResultName(result) + ".";
      return false;
    }
    if (diagnostics->struct_size != sizeof(*diagnostics) ||
        diagnostics->abi_version != KIRAKARA_FLUTTER_COMPOSITOR_ABI_VERSION ||
        diagnostics->patchset_version !=
            KIRAKARA_FLUTTER_COMPOSITOR_PATCHSET_VERSION) {
      *error =
          "Kirakara compositor diagnostics returned incompatible "
          "version metadata.";
      return false;
    }
    return true;
  }

  KirakaraFlutterCompositorApi api{};
  FlutterDesktopViewRef view{};
  HWND window{};
  bool prepared{};
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
};

DcompCompositorBridge::DcompCompositorBridge()
    : impl_(std::make_unique<Impl>()) {}

DcompCompositorBridge::~DcompCompositorBridge() { Shutdown(); }

bool DcompCompositorBridge::PrepareNextView(HWND top_level_window,
                                            std::string* error) {
  const std::string backend = ReadBackendEnvironment();
  if (backend.empty() || backend == "stock" || backend == "external_texture") {
    return true;
  }
  if (backend != "synthetic") {
    *error = "Unsupported KIRAKARA_COMPOSITOR_BACKEND='" + backend +
             "'. Expected stock, external_texture, or synthetic.";
    return false;
  }
  enabled_ = true;
  if (!top_level_window || !::IsWindow(top_level_window)) {
    *error =
        "The synthetic DirectComposition backend requires a valid "
        "top-level HWND.";
    return false;
  }
  return impl_->ResolveApi(error) && impl_->Prepare(top_level_window, error);
}

bool DcompCompositorBridge::Attach(flutter::FlutterEngine* engine,
                                   std::string* error) {
  return !enabled_ || impl_->Attach(engine, error);
}

void DcompCompositorBridge::CancelPreparedView() {
  if (impl_ && impl_->prepared && impl_->api.cancel_prepared_view) {
    impl_->api.cancel_prepared_view();
    impl_->prepared = false;
  }
}

void DcompCompositorBridge::Shutdown() {
  if (!impl_) {
    return;
  }
  CancelPreparedView();
  impl_->channel.reset();
  impl_->view = nullptr;
  impl_->window = nullptr;
}

bool DcompCompositorBridge::HandleTestResizeMessage(int32_t width_delta,
                                                    int32_t height_delta) {
  if (!enabled_ || !SyntheticTestModeEnabled() || !impl_ || !impl_->window ||
      !::IsWindow(impl_->window) || width_delta < -512 || width_delta > 512 ||
      height_delta < -512 || height_delta > 512 ||
      (width_delta == 0 && height_delta == 0)) {
    return false;
  }

  RECT bounds{};
  if (!::GetWindowRect(impl_->window, &bounds)) {
    return false;
  }
  const int64_t width = static_cast<int64_t>(bounds.right) - bounds.left +
                        static_cast<int64_t>(width_delta);
  const int64_t height = static_cast<int64_t>(bounds.bottom) - bounds.top +
                         static_cast<int64_t>(height_delta);
  if (width < 320 || height < 240 || width > 16384 || height > 16384) {
    return false;
  }
  return ::SetWindowPos(impl_->window, nullptr, 0, 0,
                        static_cast<int>(width), static_cast<int>(height),
                        SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER) != FALSE;
}

bool DcompCompositorBridge::HandleTestMoveToMonitorMessage(
    int32_t monitor_index) {
  if (!enabled_ || !SyntheticTestModeEnabled() || !impl_ || !impl_->window ||
      !::IsWindow(impl_->window) || ::IsZoomed(impl_->window) ||
      monitor_index < 0) {
    return false;
  }
  const auto monitors = EnumerateMonitors();
  if (static_cast<size_t>(monitor_index) >= monitors.size()) {
    return false;
  }

  RECT bounds{};
  if (!::GetWindowRect(impl_->window, &bounds)) {
    return false;
  }
  const LONG width = bounds.right - bounds.left;
  const LONG height = bounds.bottom - bounds.top;
  const RECT& work_area = monitors[monitor_index].work_area;
  const LONG available_width = work_area.right - work_area.left;
  const LONG available_height = work_area.bottom - work_area.top;
  const int x = work_area.left +
                std::max<LONG>(0, (available_width - width) / 2);
  const int y = work_area.top +
                std::max<LONG>(0, (available_height - height) / 2);
  return ::SetWindowPos(impl_->window, nullptr, x, y, 0, 0,
                        SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER) != FALSE;
}

void ReportDcompCompositorStartupError(HWND owner, const std::string& error) {
  const std::string debug_message =
      "Kirakara DirectComposition startup failed: " + error + "\n";
  ::OutputDebugStringA(debug_message.c_str());
  const std::wstring wide_error = Utf8ToWide(error);
  const std::wstring message =
      L"Kirakara DirectComposition 合成器启动失败。\n\n" + wide_error +
      L"\n\n请确认 App、Engine DLL 与补丁版本完全匹配。";
  ::MessageBoxW(owner, message.c_str(), L"Kirakara compositor error",
                MB_OK | MB_ICONERROR);
}
