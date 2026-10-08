#include "neura_engine_session.h"

#include <cstring>
#include <string>

namespace {
template <typename T>
T Lookup(HMODULE library, const char* name) {
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
    case 7: return "paused";
    default: return "error";
  }
}
}  // namespace

NeuraEngineSession::NeuraEngineSession(flutter::BinaryMessenger* messenger,
                                     HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "neura/engine_synthetic_session",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.arguments() != nullptr &&
        !std::holds_alternative<std::monostate>(*call.arguments())) {
      result->Error("invalid_request", "Synthetic operations accept no arguments.");
      return;
    }
    const auto& method = call.method_name();
    if (method == "stopSynthetic") {
      if (stop_) stop_();
      result->Success(flutter::EncodableValue(blocked_ ? "blocked" : "disabled"));
    } else if (method == "blockSynthetic") {
      // Latch even before the DLL has been loaded. Safe Mode/recovery cannot
      // be reversed by reopening the Console or returning to the foreground.
      blocked_ = true;
      if (block_) block_();
      result->Success(flutter::EncodableValue("blocked"));
    } else if (method == "pauseSynthetic") {
      result->Success(flutter::EncodableValue(
          blocked_ ? "blocked" : (pause_ ? StateName(pause_()) : "disabled")));
    } else if (method == "startSynthetic" || method == "resumeSynthetic") {
      if (blocked_) {
        result->Success(flutter::EncodableValue("blocked"));
        return;
      }
      if (!Load()) {
        result->Success(flutter::EncodableValue("unavailable"));
        return;
      }
      const bool visible = IsWindowVisible(window_) && !IsIconic(window_) &&
                           GetForegroundWindow() == window_;
      foreground_(visible ? 1 : 0);
      result->Success(flutter::EncodableValue(
          StateName(method == "startSynthetic" ? start_() : resume_())));
    } else if (method == "syntheticStatus") {
      result->Success(flutter::EncodableValue(
          blocked_ ? "blocked" : (status_ ? StateName(status_()) : "disabled")));
    } else {
      result->NotImplemented();
    }
  });
}

bool NeuraEngineSession::Load() {
  if (library_) return true;
  wchar_t executable[32768];
  const DWORD count = GetModuleFileNameW(nullptr, executable, 32768);
  if (count == 0 || count >= 32768) return false;
  const std::wstring path(executable, count);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  const auto library_path = path.substr(0, separator + 1) + L"neura_swarm.dll";
  library_ = LoadLibraryExW(library_path.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!library_) return false;
  start_ = Lookup<StateFunction>(library_, "neura_engine_start_synthetic");
  pause_ = Lookup<StateFunction>(library_, "neura_engine_pause_synthetic");
  resume_ = Lookup<StateFunction>(library_, "neura_engine_resume_synthetic");
  status_ = Lookup<StateFunction>(library_, "neura_engine_synthetic_status");
  stop_ = Lookup<StopFunction>(library_, "neura_engine_stop_synthetic");
  block_ = Lookup<StopFunction>(library_, "neura_engine_block_synthetic");
  foreground_ = Lookup<ForegroundFunction>(library_, "neura_engine_synthetic_foreground");
  if (start_ && pause_ && resume_ && status_ && stop_ && block_ && foreground_) return true;
  FreeLibrary(library_);
  library_ = nullptr;
  start_ = nullptr;
  pause_ = nullptr;
  resume_ = nullptr;
  status_ = nullptr;
  stop_ = nullptr;
  block_ = nullptr;
  foreground_ = nullptr;
  return false;
}

void NeuraEngineSession::Background() {
  if (foreground_) foreground_(0);
}

NeuraEngineSession::~NeuraEngineSession() {
  channel_->SetMethodCallHandler(nullptr);
  if (stop_) stop_();
  if (library_) FreeLibrary(library_);
}
