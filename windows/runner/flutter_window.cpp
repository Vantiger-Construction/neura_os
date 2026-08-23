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

  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    RecordNeuraNativeBreadcrumb("flutter_controller_create_failed");
    return false;
  }

  RecordNeuraNativeBreadcrumb("flutter_controller_created");

  auto* engine = flutter_controller_->engine();

  // Dart asks for this role immediately after attaching its dependency-free
  // bootstrap frame. Install the channel before registering plugins so window
  // role discovery cannot race the larger plugin registration sequence.
  window_role_ = std::make_unique<NeuraWindowRole>(
      engine->messenger(), window_id_, is_mascot_);

  RecordNeuraNativeBreadcrumb("window_role_channel_registered");

  if (is_mascot_) {
    // The floating avatar window runs its own, second Flutter engine.
    //
    // Several Windows Flutter plugins keep registration state in process-wide
    // globals instead of per-engine state. Registering the complete plugin set
    // again for the mascot can therefore overwrite method-channel/plugin state
    // owned by the primary window.
    //
    // flutter_tts is the most important example. The mascot does not use TTS,
    // record, secure storage, printing, auth, etc., so those plugins should not
    // be registered on this engine.
    //
    // The mascot currently uses only:
    //
    //   - window_manager_plus
    //   - screen_retriever
    //
    // Keep its plugin surface intentionally narrow.
    WindowManagerPlusPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("WindowManagerPlusPlugin"));

    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
        engine->GetRegistrarForPlugin(
            "ScreenRetrieverWindowsPluginCApi"));
  } else {
    // The primary application window owns the normal complete plugin set.
    RegisterPlugins(engine);
  }

  // A Flutter plugin can install its own process exception filter during
  // registration. Reassert Neura's native diagnostics handler afterward.
  //
  // Neura's handler only records a privacy-safe breadcrumb and returns
  // EXCEPTION_CONTINUE_SEARCH, so normal Windows crash reporting and debugging
  // behavior remain intact.
  InstallNeuraNativeCrashHandlers();

  RecordNeuraNativeBreadcrumb("plugins_registered");

  // Native speech recognition bridge.
  speech_recognizer_ =
      std::make_unique<NeuraSpeechRecognizer>(engine->messenger());

  RecordNeuraNativeBreadcrumb("native_channels_registered");

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    RecordNeuraNativeBreadcrumb(
        is_mascot_ ? "mascot_first_frame" : "primary_first_frame");

    this->Show();
  });

  // Flutter can complete its first frame before the show callback is
  // registered. ForceRedraw ensures a frame remains pending in that case.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Both custom channel owners retain the engine's BinaryMessenger.
  //
  // Destroy them before destroying FlutterViewController / FlutterEngine so a
  // teardown callback can never dereference a messenger whose engine has
  // already been released.
  window_role_.reset();
  speech_recognizer_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Give Flutter and registered plugins the first chance to handle Windows
  // messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(
            hwnd, message, wparam, lparam);

    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // A font-change broadcast can arrive while a window is being destroyed.
      // OnDestroy deliberately releases the controller, so guard both the
      // controller and engine before dereferencing them.
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(
      hwnd,
      message,
      wparam,
      lparam);
}