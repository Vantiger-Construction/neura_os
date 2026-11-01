#pragma once

#include <windows.h>
#include <sapi.h>

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "neura_tts_lifecycle.h"

struct NeuraComRelease {
  void operator()(IUnknown* value) const {
    if (value) value->Release();
  }
};
template <typename T>
using NeuraComPtr = std::unique_ptr<T, NeuraComRelease>;

// All COM and method-channel work stays on Flutter's UI/STA thread. No raw-this
// async callbacks, MediaPlayer, retained MethodResult or WinRT coroutine.
class NeuraWindowsTts {
 public:
  explicit NeuraWindowsTts(flutter::BinaryMessenger* messenger);
  ~NeuraWindowsTts();
  void Background() noexcept;

 private:
  struct Voice {
    NeuraComPtr<ISpObjectToken> token;
    std::string name;
    std::string locale;
    std::string gender;
  };
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void EnsureVoice();
  void EnsureCatalog();
  void LoadVoices();
  void Drain();
  void Stop();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NeuraComPtr<ISpVoice> voice_;
  std::vector<Voice> voices_;
  NeuraTtsLifecycle lifecycle_;
  bool catalog_loaded_ = false;
  size_t selected_voice_ = 0;
  int64_t voice_request_ = 0;
  std::wstring utterance_;
  LONG rate_ = 0;
  USHORT volume_ = 100;
  int pitch_ = 0;
  // Latest SAPI viseme (SPVISEMES 0..21) for the active utterance, or -1.
  // A mouth-shape index only: no text, phoneme string or timing leaves here.
  int viseme_ = -1;
};
