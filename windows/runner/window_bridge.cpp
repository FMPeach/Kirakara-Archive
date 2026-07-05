#include "window_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>

namespace {

using flutter::EncodableValue;
using flutter::EncodableList;
using flutter::EncodableMap;
using MethodCall = flutter::MethodCall<EncodableValue>;
using MethodResult = flutter::MethodResult<EncodableValue>;

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_window_channel;

std::string WideToUtf8(const wchar_t* text) {
  if (text == nullptr || text[0] == L'\0') {
    return {};
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return {};
  }
  std::string result(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(
      CP_UTF8, 0, text, -1, result.data(), size, nullptr, nullptr);
  return result;
}

std::string MonitorFriendlyName(const MONITORINFOEXW& info) {
  DISPLAY_DEVICEW device{};
  device.cb = sizeof(device);
  if (EnumDisplayDevicesW(info.szDevice, 0, &device, 0) &&
      device.DeviceString[0] != L'\0') {
    return WideToUtf8(device.DeviceString);
  }
  return WideToUtf8(info.szDevice);
}

BOOL CALLBACK EnumMonitorProc(
    HMONITOR monitor, HDC, LPRECT, LPARAM user_data) {
  auto* displays = reinterpret_cast<EncodableList*>(user_data);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }

  const auto& rect = info.rcMonitor;
  EncodableMap display;
  display.emplace(EncodableValue("id"), EncodableValue(WideToUtf8(info.szDevice)));
  display.emplace(EncodableValue("name"), EncodableValue(MonitorFriendlyName(info)));
  display.emplace(
      EncodableValue("isPrimary"),
      EncodableValue((info.dwFlags & MONITORINFOF_PRIMARY) != 0));
  display.emplace(EncodableValue("left"), EncodableValue(static_cast<int64_t>(rect.left)));
  display.emplace(EncodableValue("top"), EncodableValue(static_cast<int64_t>(rect.top)));
  display.emplace(
      EncodableValue("width"),
      EncodableValue(static_cast<int64_t>(rect.right - rect.left)));
  display.emplace(
      EncodableValue("height"),
      EncodableValue(static_cast<int64_t>(rect.bottom - rect.top)));
  displays->emplace_back(display);
  return TRUE;
}

EncodableList EnumerateDisplays() {
  EncodableList displays;
  EnumDisplayMonitors(
      nullptr, nullptr, EnumMonitorProc, reinterpret_cast<LPARAM>(&displays));
  return displays;
}

}  // namespace

void RegisterWindowBridge(flutter::BinaryMessenger* messenger, HWND flutter_view) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "kirakara/window",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [flutter_view](const MethodCall& call,
                     std::unique_ptr<MethodResult> result) {
        if (call.method_name() == "getFlutterViewHandle") {
          result->Success(EncodableValue(static_cast<int64_t>(
              reinterpret_cast<intptr_t>(flutter_view))));
          return;
        }
        if (call.method_name() == "getDisplays") {
          result->Success(EncodableValue(EnumerateDisplays()));
          return;
        }
        result->NotImplemented();
      });

  g_window_channel = std::move(channel);
}
