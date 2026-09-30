#pragma once

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>

// Optional verified-local Windows implementation for the
// "neura/on_device_asr" method channel. The implementation is a stub unless
// the runner is explicitly compiled with NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR.
// Even an enabled build reports unavailable until the operator supplies a
// local model directory and sets the separate runtime opt-in.
class NeuraOnDeviceAsr {
 public:
  // Worker threads only enqueue segments. Flutter channel delivery is drained
  // on the window thread through this private application message.
  static constexpr UINT kDrainMessage = WM_APP + 0x4E1;

  NeuraOnDeviceAsr(flutter::BinaryMessenger* messenger, HWND window);
  ~NeuraOnDeviceAsr();

  NeuraOnDeviceAsr(const NeuraOnDeviceAsr&) = delete;
  NeuraOnDeviceAsr& operator=(const NeuraOnDeviceAsr&) = delete;

  void DrainPendingSegments();

 private:
  struct PendingSegment {
    std::string text;
    bool is_final = false;
    uint64_t generation = 0;
  };

  class Impl;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void QueueSegment(std::string text, bool is_final, uint64_t generation);
  void ClearPendingSegments();

  HWND window_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Impl> impl_;
  std::mutex pending_mutex_;
  std::deque<PendingSegment> pending_segments_;
  uint64_t generation_ = 0;
  bool listening_ = false;
};
