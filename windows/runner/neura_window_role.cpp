#include "neura_window_role.h"

NeuraWindowRole::NeuraWindowRole(flutter::BinaryMessenger* messenger,
                                 int window_id, bool is_mascot)
    : window_id_(window_id), is_mascot_(is_mascot) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "neura/window_role",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

void NeuraWindowRole::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "getRole") {
    flutter::EncodableMap role;
    role[flutter::EncodableValue("windowId")] =
        flutter::EncodableValue(window_id_);
    role[flutter::EncodableValue("isMascot")] =
        flutter::EncodableValue(is_mascot_);
    result->Success(flutter::EncodableValue(role));
  } else {
    result->NotImplemented();
  }
}
