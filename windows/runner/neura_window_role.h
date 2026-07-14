#pragma once

// Tells each window_manager_plus engine what it actually is (main app window
// vs. the floating mascot window) and its real window id.
//
// Dart entrypoint arguments (`args` in `main()`) do not reliably reach
// secondary window_manager_plus engines in this Flutter build -- confirmed
// empty via diagnostic logging even though the native side constructs them
// correctly -- so identity is instead passed through this dedicated native
// channel, populated directly from the C++ window-creation callback in
// main.cpp where the true window id and role are already known.
//
// Wire protocol (method channel "neura/window_role"):
//   Dart -> native: "getRole" (no args)
//   native -> Dart: {"windowId": int, "isMascot": bool}

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

class NeuraWindowRole {
 public:
  NeuraWindowRole(flutter::BinaryMessenger* messenger, int window_id,
                  bool is_mascot);
  ~NeuraWindowRole() = default;

  NeuraWindowRole(const NeuraWindowRole&) = delete;
  NeuraWindowRole& operator=(const NeuraWindowRole&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  int window_id_;
  bool is_mascot_;
};
