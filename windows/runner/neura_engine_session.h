#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

// Fixed synthetic operations only. Credentials, paths, endpoints and response
// contents never cross this channel. Only the primary Windows engine owns it.
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
  bool Load();
  HWND window_;
  HMODULE library_ = nullptr;
  StateFunction start_ = nullptr;
  StateFunction status_ = nullptr;
  StopFunction stop_ = nullptr;
  StopFunction block_ = nullptr;
  ForegroundFunction foreground_ = nullptr;
  bool blocked_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
