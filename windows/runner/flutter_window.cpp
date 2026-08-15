#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "neura_native_diagnostics.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             int window_id, bool is_mascot)
    : project_(project), window_id_(window_id), is_mascot_(is_mascot) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    RecordNeuraNativeBreadcrumb("flutter_controller_create_failed");
    return false;
  }
  RecordNeuraNativeBreadcrumb("flutter_controller_created");

  // Dart asks for this role immediately after attaching its dependency-free
  // bootstrap frame. Install the channel as soon as the engine messenger
  // exists, before registering the much larger plugin set, so discovery cannot
  // race registration. NeuraWindowRole uses only Flutter's standard method
  // codec and the runner diagnostics sink; it has no plugin dependency.
  window_role_ = std::make_unique<NeuraWindowRole>(
      flutter_controller_->engine()->messenger(), window_id_, is_mascot_);
  RecordNeuraNativeBreadcrumb("window_role_channel_registered");

  RegisterPlugins(flutter_controller_->engine());
  // The engine or a plugin may install its own unhandled-exception filter.
  // Reassert Neura's pass-through logger after registration; the handler logs
  // a privacy-safe breadcrumb and still returns EXCEPTION_CONTINUE_SEARCH so
  // normal Windows crash reporting remains intact.
  InstallNeuraNativeCrashHandlers();
  RecordNeuraNativeBreadcrumb("plugins_registered");
  speech_recognizer_ = std::make_unique<NeuraSpeechRecognizer>(
      flutter_controller_->engine()->messenger());
  RecordNeuraNativeBreadcrumb("native_channels_registered");
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    RecordNeuraNativeBreadcrumb(is_mascot_ ? "mascot_first_frame"
                                           : "primary_first_frame");
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Both custom channel owners retain the engine's BinaryMessenger. Release
  // them before destroying the FlutterViewController/engine so no teardown
  // callback can dereference a messenger that has already gone away.
  window_role_.reset();
  speech_recognizer_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // A font broadcast can arrive while a window is being torn down. The
      // controller is deliberately released in OnDestroy, so never
      // dereference it from a late native message.
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
