#include "neura_local_conversation.h"
#include <cstring>
#include <string>

namespace {
template <typename T> T Lookup(HMODULE library, const char* name) {
  const FARPROC address = GetProcAddress(library, name);
  T result = nullptr;
  static_assert(sizeof(result) == sizeof(address));
  std::memcpy(&result, &address, sizeof(result));
  return result;
}
const char* StateName(int state) {
  switch (state) {
    case 0: return "disabled";
    case 1: return "starting";
    case 2: return "idle";
    case 4: return "unavailable";
    case 5: return "blocked";
    case 6: return "working";
    default: return "error";
  }
}
}  // namespace

NeuraLocalConversation::NeuraLocalConversation(
    flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "neura/local_conversation",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "send") {
      const auto* text = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!text || text->empty() || text->size() > 2048) {
        result->Error("invalid_text", "Send a shorter typed message.");
        return;
      }
      if (!Foreground()) Background();
      const bool accepted = !blocked_ && Foreground() && submit_ &&
          submit_(reinterpret_cast<const unsigned char*>(text->data()), text->size()) == 1;
      result->Success(flutter::EncodableValue(accepted));
      return;
    }
    if (call.arguments() && !std::holds_alternative<std::monostate>(*call.arguments())) {
      result->Error("invalid_request", "Session controls accept no arguments.");
      return;
    }
    if (method == "stop") {
      Background();
      result->Success();
    } else if (method == "block") {
      blocked_ = true;
      if (block_) block_();
      result->Success();
    } else if (method == "start") {
      const char* state = "blocked";
      if (!blocked_ && Foreground()) {
        state = Load() ? StateName(start_(reinterpret_cast<size_t>(window_))) : "unavailable";
      }
      result->Success(flutter::EncodableValue(state));
    } else if (method == "poll") {
      if (!Foreground()) Background();
      const int state = blocked_ ? 5 : (status_ ? status_() : 0);
      flutter::EncodableMap snapshot;
      snapshot[flutter::EncodableValue("state")] = flutter::EncodableValue(StateName(state));
      if (!blocked_ && Foreground() && state == 2 && take_) {
        unsigned char buffer[4096] = {};
        const size_t count = take_(buffer, sizeof(buffer));
        if (count > 0 && count <= sizeof(buffer)) {
          snapshot[flutter::EncodableValue("text")] = flutter::EncodableValue(
              std::string(reinterpret_cast<const char*>(buffer), count));
        }
        SecureZeroMemory(buffer, sizeof(buffer));
      }
      result->Success(flutter::EncodableValue(snapshot));
    } else {
      result->NotImplemented();
    }
  });
}

bool NeuraLocalConversation::Foreground() const {
  return IsWindowVisible(window_) && !IsIconic(window_) && GetForegroundWindow() == window_;
}
bool NeuraLocalConversation::Load() {
  if (library_) return true;
  wchar_t executable[32768];
  const DWORD count = GetModuleFileNameW(nullptr, executable, 32768);
  if (count == 0 || count >= 32768) return false;
  const std::wstring path(executable, count);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  const auto library_path = path.substr(0, separator + 1) + L"neura_swarm.dll";
  HMODULE library = LoadLibraryExW(library_path.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!library) return false;
  const auto start = Lookup<Start>(library, "neura_local_start");
  const auto status = Lookup<Status>(library, "neura_local_status");
  const auto stop = Lookup<End>(library, "neura_local_stop");
  const auto block = Lookup<End>(library, "neura_local_block");
  const auto submit = Lookup<Submit>(library, "neura_local_submit");
  const auto take = Lookup<Take>(library, "neura_local_take_reply");
  if (!start || !status || !stop || !block || !submit || !take) {
    FreeLibrary(library);
    return false;
  }
  library_ = library; start_ = start; status_ = status; stop_ = stop;
  block_ = block; submit_ = submit; take_ = take;
  return true;
}
void NeuraLocalConversation::Background() { if (stop_) stop_(); }
NeuraLocalConversation::~NeuraLocalConversation() {
  channel_->SetMethodCallHandler(nullptr);
  Background();
  if (library_) FreeLibrary(library_);
}
