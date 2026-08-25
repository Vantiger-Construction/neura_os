#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <window_manager_plus/window_manager_plus_plugin.h>

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
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    RecordNeuraNativeBreadcrumb("flutter_controller_create_failed");
    return false;
  }
  RecordNeuraNativeBreadcrumb("flutter_controller_created");

  auto* engine = flutter_controller_->engine();

  // Dart asks for this role immediately after attaching its dependency-free
  // bootstrap frame. Install the channel before plugins so discovery cannot
  // race plugin registration.
  window_role_ = std::make_unique<NeuraWindowRole>(
      engine->messenger(), window_id_, is_mascot_);
  RecordNeuraNativeBreadcrumb("window_role_channel_registered");

  if (is_mascot_) {
    // The mascot owns a second Flutter engine but uses only these two plugins.
    // Registering the complete plugin set here would duplicate process-global
    // plugin state, including flutter_tts, and could clobber the primary
    // engine's method channels. This is independent of issue #32's native TTS
    // crash and remains worthwhile even while spoken startup audio stays off.
    WindowManagerPlusPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("WindowManagerPlusPlugin"));
    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  } else {
    RegisterPlugins(engine);
  }

  // A plugin may install its own unhandled-exception filter. Reassert Neura's
  // pass-through logger afterward; it records a privacy-safe breadcrumb and
  // still returns EXCEPTION_CONTINUE_SEARCH for normal Windows reporting.
  InstallNeuraNativeCrashHandlers();
  RecordNeuraNativeBreadcrumb("plugins_registered");

  speech_recognizer_ =
      std::make_unique<NeuraSpeechRecognizer>(engine->messenger());
  RecordNeuraNativeBreadcrumb("native_channels_registered");
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    RecordNeuraNativeBreadcrumb(is_mascot_ ? "mascot_first_frame"
                                           : "primary_first_frame");
    this->Show();
  });

  // Flutter can complete the first frame before the show callback is
  // registered. This ensures a frame is pending; it is a no-op otherwise.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Both custom channel owners retain the engine's BinaryMessenger. Release
  // them before destroying the FlutterViewController/engine.
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
      // A font broadcast can arrive while a window is being torn down.
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
