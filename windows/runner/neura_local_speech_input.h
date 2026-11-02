#pragma once

#include <windows.h>
#include <sapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

// A separate on-device input path. All COM/channel work stays on the main STA;
// polling avoids native callbacks retaining this owner across window teardown.
class NeuraLocalSpeechInput {
 public:
  NeuraLocalSpeechInput(flutter::BinaryMessenger* messenger, HWND window);
  ~NeuraLocalSpeechInput();
  void Background() noexcept;

 private:
  struct Release { void operator()(IUnknown* p) const { if (p) p->Release(); } };
  template <typename T> using ComPtr = std::unique_ptr<T, Release>;
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  ComPtr<ISpObjectToken> FindEngine();
  void Start(int64_t session);
  flutter::EncodableMap Poll();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
  ComPtr<ISpRecognizer> recognizer_;
  ComPtr<ISpAudio> audio_;
  ComPtr<ISpRecoContext> context_;
  ComPtr<ISpRecoGrammar> grammar_;
  int64_t session_ = 0;
};
