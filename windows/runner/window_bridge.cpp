#include "window_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>

namespace {

using flutter::EncodableValue;
using MethodCall = flutter::MethodCall<EncodableValue>;
using MethodResult = flutter::MethodResult<EncodableValue>;

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_window_channel;

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
        result->NotImplemented();
      });

  g_window_channel = std::move(channel);
}
