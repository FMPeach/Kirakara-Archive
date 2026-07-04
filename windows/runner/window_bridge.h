#ifndef RUNNER_WINDOW_BRIDGE_H_
#define RUNNER_WINDOW_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterWindowBridge(flutter::BinaryMessenger* messenger, HWND flutter_view);

#endif  // RUNNER_WINDOW_BRIDGE_H_
