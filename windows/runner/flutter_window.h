#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "neura_on_device_asr.h"
#include "neura_engine_session.h"
#include "neura_speech_recognizer.h"
#include "neura_window_role.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |window_id| and |is_mascot| are handed to the Dart side over the
  // "neura/window_role" channel -- see neura_window_role.h for why that's
  // needed instead of dart_entrypoint_arguments.
  explicit FlutterWindow(const flutter::DartProject& project,
                         int window_id = 0, bool is_mascot = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native speech-to-text bridge for the chat mic button (main window only
  // uses it in practice, but it's harmless and idle on sub-windows).
  std::unique_ptr<NeuraSpeechRecognizer> speech_recognizer_;

  // Experimental verified-local ONNX path. It is registered only on the
  // primary engine and remains unavailable unless both build-time and runtime
  // opt-ins plus local model files are present.
  std::unique_ptr<NeuraOnDeviceAsr> on_device_asr_;
  std::unique_ptr<NeuraEngineSession> engine_session_;

  int window_id_;
  bool is_mascot_;
  std::unique_ptr<NeuraWindowRole> window_role_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
