#include "neura_speech_recognizer.h"

#include <windows.h>

#include <string>

NeuraSpeechRecognizer::NeuraSpeechRecognizer(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "neura/speech_recognition",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

NeuraSpeechRecognizer::~NeuraSpeechRecognizer() {
#if defined(WINAPI_FAMILY) && (WINAPI_FAMILY == WINAPI_FAMILY_DESKTOP_APP)
  if (initialized_) {
    recognizer_.ContinuousRecognitionSession().ResultGenerated(result_token_);
    recognizer_.HypothesisGenerated(hypothesis_token_);
    recognizer_.ContinuousRecognitionSession().Completed(completed_token_);
  }
#endif
}

void NeuraSpeechRecognizer::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
#if defined(WINAPI_FAMILY) && (WINAPI_FAMILY == WINAPI_FAMILY_DESKTOP_APP)
  if (call.method_name() == "start") {
    StartListening();
    result->Success(flutter::EncodableValue(true));
  } else if (call.method_name() == "stop") {
    StopListening();
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
#else
  result->Success(flutter::EncodableValue(false));
#endif
}

#if defined(WINAPI_FAMILY) && (WINAPI_FAMILY == WINAPI_FAMILY_DESKTOP_APP)

using winrt::Windows::Media::SpeechRecognition::SpeechContinuousRecognitionCompletedEventArgs;
using winrt::Windows::Media::SpeechRecognition::SpeechContinuousRecognitionResultGeneratedEventArgs;
using winrt::Windows::Media::SpeechRecognition::SpeechRecognitionHypothesisGeneratedEventArgs;
using winrt::Windows::Media::SpeechRecognition::SpeechRecognitionResultStatus;
using winrt::Windows::Media::SpeechRecognition::SpeechRecognitionScenario;
using winrt::Windows::Media::SpeechRecognition::SpeechRecognitionTopicConstraint;
using winrt::Windows::Media::SpeechRecognition::SpeechRecognizer;

winrt::Windows::Foundation::IAsyncAction NeuraSpeechRecognizer::EnsureInitialized() {
  if (initialized_) {
    co_return;
  }

  recognizer_ = SpeechRecognizer();
  recognizer_.Constraints().Append(
      SpeechRecognitionTopicConstraint(SpeechRecognitionScenario::Dictation, L"dictation"));

  result_token_ = recognizer_.ContinuousRecognitionSession().ResultGenerated(
      [this](auto&&, SpeechContinuousRecognitionResultGeneratedEventArgs const& args) {
        auto text = winrt::to_string(args.Result().Text());
        if (!text.empty()) {
          channel_->InvokeMethod("onFinal",
              std::make_unique<flutter::EncodableValue>(text));
        }
      });

  hypothesis_token_ = recognizer_.HypothesisGenerated(
      [this](auto&&, SpeechRecognitionHypothesisGeneratedEventArgs const& args) {
        auto text = winrt::to_string(args.Hypothesis().Text());
        channel_->InvokeMethod("onPartial",
            std::make_unique<flutter::EncodableValue>(text));
      });

  completed_token_ = recognizer_.ContinuousRecognitionSession().Completed(
      [this](auto&&, SpeechContinuousRecognitionCompletedEventArgs const&) {
        listening_ = false;
        channel_->InvokeMethod("onStopped", nullptr);
      });

  try {
    auto compilation = co_await recognizer_.CompileConstraintsAsync();
    if (compilation.Status() != SpeechRecognitionResultStatus::Success) {
      channel_->InvokeMethod("onError",
          std::make_unique<flutter::EncodableValue>(std::string("compile_failed")));
      co_return;
    }
    initialized_ = true;
  } catch (...) {
    channel_->InvokeMethod("onError",
        std::make_unique<flutter::EncodableValue>(std::string("init_failed")));
  }
}

winrt::Windows::Foundation::IAsyncAction NeuraSpeechRecognizer::StartListening() {
  co_await EnsureInitialized();
  if (!initialized_ || listening_) {
    co_return;
  }

  try {
    listening_ = true;
    channel_->InvokeMethod("onListening", nullptr);
    co_await recognizer_.ContinuousRecognitionSession().StartAsync();
  } catch (...) {
    listening_ = false;
    channel_->InvokeMethod("onError",
        std::make_unique<flutter::EncodableValue>(std::string("start_failed")));
  }
}

winrt::Windows::Foundation::IAsyncAction NeuraSpeechRecognizer::StopListening() {
  if (!initialized_ || !listening_) {
    co_return;
  }

  try {
    co_await recognizer_.ContinuousRecognitionSession().StopAsync();
  } catch (...) {
    // Best-effort stop; nothing actionable if this fails.
  }
  listening_ = false;
}

#endif  // WINAPI_FAMILY_DESKTOP_APP
