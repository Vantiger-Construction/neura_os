#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <window_manager_plus/window_manager_plus_plugin.h>

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
    return false;
  }
  if (is_mascot_) {
    // The floating avatar window runs its own, second Flutter engine (see
    // WindowManagerPlusPluginSetWindowCreatedCallback in main.cpp). Several
    // of this app's Windows plugins -- flutter_tts in particular -- keep
    // their registration state in file-scope global variables rather than
    // per-engine state, because they were never written with multi-engine
    // apps in mind. Calling the full RegisterPlugins() here would register
    // a second flutter_tts_plugin instance and clobber the main window's
    // plugin/method-channel state out from under any in-flight or
    // about-to-fire TTS call -- a real bug, worth fixing regardless.
    //
    // NOTE: this does NOT fix the flutter_tts_plugin.dll crash tracked in
    // issue #32. That was directly tested and disproven -- the crash still
    // reproduces 100% of the time with this fix applied, and even with the
    // mascot window disabled entirely (no second engine created at all).
    // The real cause is inside flutter_tts's own Windows speak()
    // implementation; see the corrected diagnosis in
    // lib/services/ambient_listening_service.dart's kEnableProactiveGreetingTts
    // doc comment. This registration fix stays because it's a real,
    // separate bug (a latent footgun for any future plugin that also uses
    // global state), not because it resolves #32.
    //
    // The mascot window's Dart code (lib/mascot/*.dart) only ever calls
    // into window_manager_plus and screen_retriever, so only register
    // those two plugins for this engine instead of the full set. This also
    // sidesteps the same process-global-state footgun in any of the other
    // ten plugins below, not just flutter_tts.
    auto* engine = flutter_controller_->engine();
    WindowManagerPlusPluginRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("WindowManagerPlusPlugin"));
    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
        engine->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  } else {
    RegisterPlugins(flutter_controller_->engine());
  }
  speech_recognizer_ = std::make_unique<NeuraSpeechRecognizer>(
      flutter_controller_->engine()->messenger());
  window_role_ = std::make_unique<NeuraWindowRole>(
      flutter_controller_->engine()->messenger(), window_id_, is_mascot_);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
