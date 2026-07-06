#include "window_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>
#include <variant>

namespace {

using flutter::EncodableValue;
using flutter::EncodableList;
using flutter::EncodableMap;
using MethodCall = flutter::MethodCall<EncodableValue>;
using MethodResult = flutter::MethodResult<EncodableValue>;

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_window_channel;
bool g_controller_fullscreen = false;
DWORD g_controller_restore_style = 0;
DWORD g_controller_restore_ex_style = 0;
WINDOWPLACEMENT g_controller_restore_placement{sizeof(WINDOWPLACEMENT)};

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

HWND ControllerWindowFromFlutterView(HWND flutter_view) {
  if (!flutter_view) {
    return nullptr;
  }
  HWND root = GetAncestor(flutter_view, GA_ROOT);
  return root ? root : flutter_view;
}

bool ReadBoolArgument(const EncodableValue* value, bool fallback) {
  if (!value) {
    return fallback;
  }
  if (const auto* bool_value = std::get_if<bool>(value)) {
    return *bool_value;
  }
  return fallback;
}

bool SetControllerFullscreen(HWND flutter_view, bool fullscreen) {
  HWND window = ControllerWindowFromFlutterView(flutter_view);
  if (!window) {
    return false;
  }
  if (g_controller_fullscreen == fullscreen) {
    return true;
  }

  if (fullscreen) {
    g_controller_restore_style =
        static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE));
    g_controller_restore_ex_style =
        static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
    g_controller_restore_placement = WINDOWPLACEMENT{sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(window, &g_controller_restore_placement);

    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    if (!GetMonitorInfoW(monitor, &monitor_info)) {
      return false;
    }

    SetWindowLongPtrW(
        window,
        GWL_STYLE,
        g_controller_restore_style & ~(WS_CAPTION | WS_THICKFRAME));
    SetWindowLongPtrW(
        window,
        GWL_EXSTYLE,
        g_controller_restore_ex_style &
            ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE |
              WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));

    const RECT& rect = monitor_info.rcMonitor;
    SetWindowPos(
        window,
        nullptr,
        rect.left,
        rect.top,
        rect.right - rect.left,
        rect.bottom - rect.top,
        SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED |
            SWP_SHOWWINDOW);
    g_controller_fullscreen = true;
    return true;
  }

  SetWindowLongPtrW(window, GWL_STYLE, g_controller_restore_style);
  SetWindowLongPtrW(window, GWL_EXSTYLE, g_controller_restore_ex_style);
  SetWindowPlacement(window, &g_controller_restore_placement);
  SetWindowPos(
      window,
      nullptr,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
          SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  g_controller_fullscreen = false;
  return true;
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
        if (call.method_name() == "isControllerFullscreen") {
          result->Success(EncodableValue(g_controller_fullscreen));
          return;
        }
        if (call.method_name() == "setControllerFullscreen") {
          const bool fullscreen =
              ReadBoolArgument(call.arguments(), !g_controller_fullscreen);
          const bool ok = SetControllerFullscreen(flutter_view, fullscreen);
          result->Success(
              EncodableValue(ok && g_controller_fullscreen == fullscreen));
          return;
        }
        result->NotImplemented();
      });

  g_window_channel = std::move(channel);
}
