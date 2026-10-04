#pragma once

// Native Windows speech-to-text bridge for the chat mic button. The
// `speech_to_text` pub.dev package this app otherwise depends on has no
// Windows implementation (Android/iOS/web/macOS only), so this talks to
// Windows' own WinRT continuous dictation recognizer directly, the same way
// flutter_tts's windows plugin talks to WinRT SpeechSynthesizer for output.
//
// Wire protocol (method channel "neura/speech_recognition"):
//   Dart -> native: "start", "stop"
//   Dart -> native: "isAvailable"
//   native -> Dart: "onListening" (no args), "onPartial" (String),
//                   "onFinal" ({text: String, confidence: double}),
//                   "onStopped" (no args),
//                   "onError" (String reason)

// Must come before any other Windows header so WINAPI_FAMILY is defined
// before the #if guard below is evaluated.
#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#if defined(WINAPI_FAMILY) && (WINAPI_FAMILY == WINAPI_FAMILY_DESKTOP_APP)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.SpeechRecognition.h>
#endif

class NeuraSpeechRecognizer {
 public:
  explicit NeuraSpeechRecognizer(flutter::BinaryMessenger* messenger);
  ~NeuraSpeechRecognizer();

  NeuraSpeechRecognizer(const NeuraSpeechRecognizer&) = delete;
  NeuraSpeechRecognizer& operator=(const NeuraSpeechRecognizer&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

#if defined(WINAPI_FAMILY) && (WINAPI_FAMILY == WINAPI_FAMILY_DESKTOP_APP)
  winrt::Windows::Foundation::IAsyncAction EnsureInitialized();
  winrt::Windows::Foundation::IAsyncAction StartListening();
  winrt::Windows::Foundation::IAsyncAction StopListening();

  winrt::Windows::Media::SpeechRecognition::SpeechRecognizer recognizer_{nullptr};
  winrt::event_token result_token_{};
  winrt::event_token hypothesis_token_{};
  winrt::event_token completed_token_{};
  bool initialized_ = false;
  bool listening_ = false;
#endif
};
