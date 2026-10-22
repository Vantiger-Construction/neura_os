#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <memory>
#include <string>

#include "flutter_window.h"
#include "neura_native_diagnostics.h"
#include "utils.h"

#include "window_manager_plus/window_manager_plus_plugin.h"

namespace {

struct HandleCloser {
  void operator()(void *handle) const noexcept {
    if (handle != nullptr) {
      ::CloseHandle(handle);
    }
  }
};

using UniqueHandle = std::unique_ptr<void, HandleCloser>;

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Keep the package launch probe native-only. Starting Flutter initializes
  // plugins and can leave background platform work alive after Dart exits.
  for (const auto &argument : GetCommandLineArguments()) {
    if (argument == "--launch-smoke-test") {
      return 73;
    }
  }

  HANDLE raw_instance_mutex = ::CreateMutexW(
      nullptr, FALSE, L"Local\\NeuraCompanionPrimaryInstance-v1");
  const DWORD mutex_result = ::GetLastError();
  UniqueHandle instance_mutex(raw_instance_mutex);
  if (!instance_mutex) {
    return EXIT_FAILURE;
  }
  if (mutex_result == ERROR_ALREADY_EXISTS) {
    return EXIT_SUCCESS;
  }

  InitializeNeuraNativeDiagnostics();

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
  RecordNeuraNativeBreadcrumb("primary_window_create_started");
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Neura", origin, size)) {
    RecordNeuraNativeBreadcrumb("primary_window_create_failed");
    return EXIT_FAILURE;
  }
  RecordNeuraNativeBreadcrumb("primary_window_created");
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
        RecordNeuraNativeBreadcrumb("secondary_window_create_started");
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
        if (sub_window->Create(L"Neura", sub_origin, sub_size)) {
          RecordNeuraNativeBreadcrumb("secondary_window_created");
          sub_window->Show();
          sub_window->SetQuitOnClose(false);
        } else {
          RecordNeuraNativeBreadcrumb("secondary_window_create_failed");
        }
        return sub_window;
      });
  RecordNeuraNativeBreadcrumb("secondary_window_callback_ready");

  ::MSG msg;
  BOOL message_result = 0;
  while ((message_result = ::GetMessage(&msg, nullptr, 0, 0)) > 0) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  RecordNeuraNativeBreadcrumb(message_result == 0 ? "message_loop_exit"
                                                   : "message_loop_error");

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
