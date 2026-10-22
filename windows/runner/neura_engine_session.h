#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <cstdint>

// Primary Windows owner for the fixed synthetic protocol and the separate,
// explicitly selected text-only Ollama request path. Endpoints and credentials
// are never accepted from Dart.
class NeuraEngineSession {
 public:
  NeuraEngineSession(flutter::BinaryMessenger* messenger, HWND window);
  ~NeuraEngineSession();
  NeuraEngineSession(const NeuraEngineSession&) = delete;
  NeuraEngineSession& operator=(const NeuraEngineSession&) = delete;
  void Background();

 private:
  using StateFunction = int (*)();
  using StopFunction = void (*)();
  using ForegroundFunction = void (*)(int);
  using OllamaBegin = int64_t (*)(const unsigned char*, size_t);
  using OllamaPoll = int (*)(int64_t, unsigned char*, size_t);
  using OllamaCancel = void (*)(int64_t);
  using OllamaTiming = int (*)(int64_t, uint64_t*, size_t);
  bool Load();
  HWND window_;
  HMODULE library_ = nullptr;
  StateFunction start_ = nullptr;
  StateFunction start_local_ = nullptr;
  StateFunction pause_ = nullptr;
  StateFunction resume_ = nullptr;
  StateFunction status_ = nullptr;
  StopFunction stop_ = nullptr;
  StopFunction block_ = nullptr;
  ForegroundFunction foreground_ = nullptr;
  bool blocked_ = false;
  OllamaBegin ollama_begin_ = nullptr;
  OllamaPoll ollama_poll_ = nullptr;
  OllamaCancel ollama_cancel_ = nullptr;
  OllamaTiming ollama_timing_ = nullptr;
  StopFunction ollama_clear_timing_ = nullptr;
  ForegroundFunction ollama_foreground_ = nullptr;
  StopFunction ollama_block_ = nullptr;
  StopFunction ollama_shutdown_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};


