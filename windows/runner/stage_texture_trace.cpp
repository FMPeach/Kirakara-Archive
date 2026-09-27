#include "stage_texture_trace.h"

#include <windows.h>
#include <TraceLoggingProvider.h>

#include <mutex>

TRACELOGGING_DEFINE_PROVIDER(
    g_kirakara_stage_texture_provider,
    "Kirakara.App.StageTexture",
    (0x6862b681, 0x4cdb, 0x45e5, 0x93, 0x6c, 0x05, 0xd8, 0x2d, 0x83,
     0xef, 0x9a));

namespace {

constexpr ULONGLONG kFrameKeyword = 0x1;
constexpr UCHAR kInfoLevel = 4;
constexpr UCHAR kVerboseLevel = 5;
std::mutex g_provider_mutex;
std::uint32_t g_provider_users{};

std::uint64_t QpcNow() {
  LARGE_INTEGER value{};
  return ::QueryPerformanceCounter(&value)
             ? static_cast<std::uint64_t>(value.QuadPart)
             : 0;
}

}  // namespace

namespace stage_texture_trace {

void RegisterProvider() {
  std::lock_guard lock(g_provider_mutex);
  if (g_provider_users++ == 0) {
    TraceLoggingRegister(g_kirakara_stage_texture_provider);
  }
}

void UnregisterProvider() {
  std::lock_guard lock(g_provider_mutex);
  if (g_provider_users == 0 || --g_provider_users != 0) {
    return;
  }
  TraceLoggingUnregister(g_kirakara_stage_texture_provider);
}

void Attach(std::uint64_t host_address, std::int64_t texture_id,
            bool succeeded) {
  if (!TraceLoggingProviderEnabled(
          g_kirakara_stage_texture_provider, kInfoLevel, kFrameKeyword)) {
    return;
  }
  TraceLoggingWrite(
      g_kirakara_stage_texture_provider, "Attach",
      TraceLoggingLevel(kInfoLevel),
      TraceLoggingKeyword(kFrameKeyword), TraceLoggingUInt64(QpcNow(), "Qpc"),
      TraceLoggingUInt64(host_address, "HostAddress"),
      TraceLoggingInt64(texture_id, "TextureId"),
      TraceLoggingBool(succeeded, "Succeeded"),
      TraceLoggingUInt32(::GetCurrentThreadId(), "ThreadId"));
}

void SetActive(bool active, std::int64_t texture_id) {
  if (!TraceLoggingProviderEnabled(
          g_kirakara_stage_texture_provider, kInfoLevel, kFrameKeyword)) {
    return;
  }
  TraceLoggingWrite(
      g_kirakara_stage_texture_provider, "SetActive",
      TraceLoggingLevel(kInfoLevel),
      TraceLoggingKeyword(kFrameKeyword), TraceLoggingUInt64(QpcNow(), "Qpc"),
      TraceLoggingBool(active, "Active"),
      TraceLoggingInt64(texture_id, "TextureId"),
      TraceLoggingUInt32(::GetCurrentThreadId(), "ThreadId"));
}

void TextureCallback(std::uint64_t generation, std::uint64_t frame_id) {
  if (!TraceLoggingProviderEnabled(
          g_kirakara_stage_texture_provider, kVerboseLevel, kFrameKeyword)) {
    return;
  }
  TraceLoggingWrite(
      g_kirakara_stage_texture_provider, "TextureCallback",
      TraceLoggingLevel(kVerboseLevel),
      TraceLoggingKeyword(kFrameKeyword), TraceLoggingUInt64(QpcNow(), "Qpc"),
      TraceLoggingUInt64(generation, "Generation"),
      TraceLoggingUInt64(frame_id, "FrameId"),
      TraceLoggingUInt32(::GetCurrentThreadId(), "ThreadId"));
}

void FrameAvailable(std::uint64_t generation, std::uint64_t frame_id,
                    std::int64_t texture_id) {
  if (!TraceLoggingProviderEnabled(
          g_kirakara_stage_texture_provider, kVerboseLevel, kFrameKeyword)) {
    return;
  }
  TraceLoggingWrite(
      g_kirakara_stage_texture_provider, "FrameAvailable",
      TraceLoggingLevel(kVerboseLevel),
      TraceLoggingKeyword(kFrameKeyword), TraceLoggingUInt64(QpcNow(), "Qpc"),
      TraceLoggingUInt64(generation, "Generation"),
      TraceLoggingUInt64(frame_id, "FrameId"),
      TraceLoggingInt64(texture_id, "TextureId"),
      TraceLoggingUInt32(::GetCurrentThreadId(), "ThreadId"));
}

void TextureAcquire(std::uint64_t generation, std::uint64_t frame_id,
                    bool advanced) {
  if (!TraceLoggingProviderEnabled(
          g_kirakara_stage_texture_provider, kVerboseLevel, kFrameKeyword)) {
    return;
  }
  TraceLoggingWrite(
      g_kirakara_stage_texture_provider, "TextureAcquire",
      TraceLoggingLevel(kVerboseLevel),
      TraceLoggingKeyword(kFrameKeyword), TraceLoggingUInt64(QpcNow(), "Qpc"),
      TraceLoggingUInt64(generation, "Generation"),
      TraceLoggingUInt64(frame_id, "FrameId"),
      TraceLoggingBool(advanced, "Advanced"),
      TraceLoggingUInt32(::GetCurrentThreadId(), "ThreadId"));
}

}  // namespace stage_texture_trace
