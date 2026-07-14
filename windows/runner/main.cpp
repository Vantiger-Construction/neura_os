#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

#include "window_manager_plus/window_manager_plus_plugin.h"

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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, /*window_id=*/0, /*is_mascot=*/false);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"neuro_companion", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // window_manager_plus (used for the floating avatar window) creates
  // additional windows by re-invoking this same entrypoint's Dart side with
  // a fresh engine; this callback does the native-side window creation for
  // each one. Sub-windows don't quit the app when closed.
  //
  // command_line_arguments (["<windowId>", "neura_mascot"], built natively
  // by window_manager_plus) is still forwarded via
  // set_dart_entrypoint_arguments for completeness, but the Dart side does
  // NOT rely on it: dart_entrypoint_arguments do not reliably reach a
  // secondary engine created in the same process on this Flutter build
  // (confirmed empty via diagnostic logging even though this vector is
  // correctly populated here). The window id and mascot flag are instead
  // parsed here, natively, and handed to Dart over the dedicated
  // "neura/window_role" channel -- see neura_window_role.h.
  WindowManagerPlusPluginSetWindowCreatedCallback(
      [](std::vector<std::string> command_line_arguments) {
        flutter::DartProject sub_project(L"data");
        sub_project.set_dart_entrypoint_arguments(command_line_arguments);

        int sub_window_id = 0;
        if (!command_line_arguments.empty()) {
          try {
            sub_window_id = std::stoi(command_line_arguments[0]);
          } catch (...) {
          }
        }

        auto sub_window = std::make_shared<FlutterWindow>(
            sub_project, sub_window_id, /*is_mascot=*/true);
        Win32Window::Point sub_origin(10, 10);
        Win32Window::Size sub_size(1280, 720);
        if (sub_window->Create(L"neuro_companion", sub_origin, sub_size)) {
          sub_window->Show();
          sub_window->SetQuitOnClose(false);
        }
        return sub_window;
      });

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
