#ifndef NEURA_LOCAL_CONVERSATION_H_
#define NEURA_LOCAL_CONVERSATION_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

class NeuraLocalConversation {
 public:
  NeuraLocalConversation(flutter::BinaryMessenger* messenger, HWND window);
  ~NeuraLocalConversation();
  void Background();
 private:
  bool Load();
  bool Foreground() const;
  HWND window_;
  bool blocked_ = false;
  HMODULE library_ = nullptr;
  using Start = int (*)(size_t);
  using Status = int (*)();
  using End = void (*)();
  using Submit = int (*)(const unsigned char*, size_t);
  using Take = size_t (*)(unsigned char*, size_t);
  Start start_ = nullptr;
  Status status_ = nullptr;
  End stop_ = nullptr;
  End block_ = nullptr;
  Submit submit_ = nullptr;
  Take take_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
