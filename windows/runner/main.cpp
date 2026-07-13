#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "ime_bridge.h"
#include "utils.h"

namespace {

class ScopedExecutionState {
 public:
  ScopedExecutionState()
      : active_(::SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED |
                                          ES_DISPLAY_REQUIRED) != 0) {}

  ~ScopedExecutionState() {
    if (active_) {
      ::SetThreadExecutionState(ES_CONTINUOUS);
    }
  }

  ScopedExecutionState(const ScopedExecutionState&) = delete;
  ScopedExecutionState& operator=(const ScopedExecutionState&) = delete;

 private:
  bool active_ = false;
};

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  if (command_line_arguments.size() >= 2 &&
      command_line_arguments[0] == "--kirakara-ime-probe") {
    const std::wstring output_path =
        std::wstring(command_line_arguments[1].begin(),
                     command_line_arguments[1].end());
    const bool ok = RunImeBridgeSelfTest(output_path);
    ::CoUninitialize();
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Keep the controller and every attached stage display awake while the app
  // is running. The previous execution state is restored on every exit path.
  ScopedExecutionState execution_state;

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1600, 900);
  if (!window.Create(L"kirakara_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
