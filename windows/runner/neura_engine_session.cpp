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
    case 8: return "model_unavailable";
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
    const auto& method = call.method_name();
    // Explicit text-only Ollama operations share the native window owner,
    // while the original synthetic protocol keeps its no-argument boundary.
    if (method == "blockOllama") {
      blocked_ = true;
      if (ollama_block_) ollama_block_();
      result->Success();
      return;
    }
    if (method == "readOfflineMemory") {
      // Explicit content-free OS query: no DLL load, daemon call or inference.
      if ((call.arguments() &&
           !std::holds_alternative<std::monostate>(*call.arguments())) ||
          blocked_ || !IsWindowVisible(window_) || IsIconic(window_) ||
          GetForegroundWindow() != window_) {
        result->Error("local_unavailable", "Memory snapshot is unavailable.");
        return;
      }
      MEMORYSTATUSEX memory = {};
      memory.dwLength = sizeof(memory);
      if (!GlobalMemoryStatusEx(&memory)) {
        result->Success();
        return;
      }
      flutter::EncodableMap snapshot;
      snapshot[flutter::EncodableValue("totalMiB")] =
          flutter::EncodableValue(static_cast<int64_t>(memory.ullTotalPhys / (1024 * 1024)));
      snapshot[flutter::EncodableValue("availableMiB")] =
          flutter::EncodableValue(static_cast<int64_t>(memory.ullAvailPhys / (1024 * 1024)));
      result->Success(flutter::EncodableValue(snapshot));
      return;
    }
    if (method == "beginOllama") {
      const auto* input = call.arguments() == nullptr ? nullptr :
          std::get_if<std::string>(call.arguments());
      if (!input || input->empty() || input->size() > 16384 || blocked_ || !Load()) {
        result->Error("local_unavailable", "Offline chat is unavailable.");
        return;
      }
      const bool visible = IsWindowVisible(window_) && !IsIconic(window_) &&
                           GetForegroundWindow() == window_;
      ollama_foreground_(visible ? 1 : 0);
      const auto id = ollama_begin_(
          reinterpret_cast<const unsigned char*>(input->data()), input->size());
      if (id <= 0) result->Error("local_unavailable", "Offline chat is unavailable or busy.");
      else result->Success(flutter::EncodableValue(id));
      return;
    }
    if (method == "clearOllamaTiming") {
      if (call.arguments() &&
          !std::holds_alternative<std::monostate>(*call.arguments())) {
        result->Error("invalid_request", "Timing clear accepts no arguments.");
        return;
      }
      if (ollama_clear_timing_) ollama_clear_timing_();
      result->Success();
      return;
    }
    if (method == "pollOllama" || method == "cancelOllama" ||
        method == "readOllamaTiming") {
      const auto* id = call.arguments() == nullptr ? nullptr :
          std::get_if<int64_t>(call.arguments());
      // StandardMethodCodec encodes small Dart ints as int32_t.
      const auto* small_id = call.arguments() == nullptr ? nullptr :
          std::get_if<int32_t>(call.arguments());
      if ((!id && !small_id) || !library_) {
        result->Error("local_unavailable", "Offline chat is unavailable.");
        return;
      }
      const int64_t generation = id ? *id : *small_id;
      if (method == "readOllamaTiming") {
        const bool visible = IsWindowVisible(window_) && !IsIconic(window_) &&
                             GetForegroundWindow() == window_;
        if (!visible) Background();
        uint64_t values[7] = {};
        if (blocked_ || !visible || !ollama_timing_ ||
            ollama_timing_(generation, values, 7) != 7 || values[0] != 1 ||
            values[1] > 4) {
          result->Success();
          return;
        }
        // Fixed numeric ABI only: no daemon strings, errors or request text.
        const char* keys[] = {"version", "outcome", "preflightUs", "inferenceUs",
                              "deliveryUs", "cancellationUs", "totalUs"};
        flutter::EncodableMap timing;
        for (size_t index = 0; index < 7; ++index) {
          timing[flutter::EncodableValue(keys[index])] = values[index] == UINT64_MAX
              ? flutter::EncodableValue()
              : flutter::EncodableValue(static_cast<int64_t>(values[index]));
        }
        result->Success(flutter::EncodableValue(timing));
        return;
      }
      if (method == "cancelOllama") {
        ollama_cancel_(generation);
        result->Success();
        return;
      }
      unsigned char buffer[8192];
      const auto count = ollama_poll_(generation, buffer, sizeof(buffer));
      if (count > 0 && count <= static_cast<int>(sizeof(buffer))) {
        const std::string text(reinterpret_cast<const char*>(buffer), count);
        SecureZeroMemory(buffer, sizeof(buffer));
        result->Success(flutter::EncodableValue(text));
      } else if (count == 0) result->Success();
      else result->Error("local_unavailable", "Offline request stopped or failed. Check Ollama and the installed model.");
      return;
    }
    if (call.arguments() != nullptr &&
        !std::holds_alternative<std::monostate>(*call.arguments())) {
      result->Error("invalid_request", "Synthetic operations accept no arguments.");
      return;
    }
    if (method == "stopSynthetic") {
      if (stop_) stop_();
      result->Success(flutter::EncodableValue(blocked_ ? "blocked" : "disabled"));
    } else if (method == "blockSynthetic") {
      // Latch even before the DLL has been loaded. Safe Mode/recovery cannot
      // be reversed by reopening the Console or returning to the foreground.
      blocked_ = true;
      if (block_) block_();
      if (ollama_block_) ollama_block_();
      result->Success(flutter::EncodableValue("blocked"));
    } else if (method == "pauseSynthetic") {
      result->Success(flutter::EncodableValue(
          blocked_ ? "blocked" : (pause_ ? StateName(pause_()) : "disabled")));
    } else if (method == "startSynthetic" || method == "startLocalCheck" ||
               method == "resumeSynthetic") {
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
      // The local adapter is chosen only by this fixed, argument-free method;
      // Resume keeps whichever adapter the paused session was started on.
      const int state = method == "startSynthetic"    ? start_()
                        : method == "startLocalCheck" ? start_local_()
                                                      : resume_();
      result->Success(flutter::EncodableValue(StateName(state)));
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
  start_local_ = Lookup<StateFunction>(library_, "neura_engine_start_local_check");
  pause_ = Lookup<StateFunction>(library_, "neura_engine_pause_synthetic");
  resume_ = Lookup<StateFunction>(library_, "neura_engine_resume_synthetic");
  status_ = Lookup<StateFunction>(library_, "neura_engine_synthetic_status");
  stop_ = Lookup<StopFunction>(library_, "neura_engine_stop_synthetic");
  block_ = Lookup<StopFunction>(library_, "neura_engine_block_synthetic");
  foreground_ = Lookup<ForegroundFunction>(library_, "neura_engine_synthetic_foreground");
  ollama_begin_ = Lookup<OllamaBegin>(library_, "neura_ollama_begin");
  ollama_poll_ = Lookup<OllamaPoll>(library_, "neura_ollama_poll");
  ollama_cancel_ = Lookup<OllamaCancel>(library_, "neura_ollama_cancel");
  // Optional for compatibility with an older packaged Rust DLL.
  ollama_timing_ = Lookup<OllamaTiming>(library_, "neura_ollama_timing");
  ollama_clear_timing_ = Lookup<StopFunction>(library_, "neura_ollama_clear_timing");
  ollama_foreground_ = Lookup<ForegroundFunction>(library_, "neura_ollama_foreground");
  ollama_block_ = Lookup<StopFunction>(library_, "neura_ollama_block");
  ollama_shutdown_ = Lookup<StopFunction>(library_, "neura_ollama_shutdown");
  if (start_ && start_local_ && pause_ && resume_ && status_ && stop_ && block_ && foreground_ &&
      ollama_begin_ && ollama_poll_ && ollama_cancel_ && ollama_foreground_ && ollama_block_ && ollama_shutdown_) return true;
  FreeLibrary(library_);
  library_ = nullptr;
  start_ = nullptr;
  start_local_ = nullptr;
  pause_ = nullptr;
  resume_ = nullptr;
  status_ = nullptr;
  stop_ = nullptr;
  block_ = nullptr;
  foreground_ = nullptr;
  ollama_begin_ = nullptr;
  ollama_poll_ = nullptr;
  ollama_cancel_ = nullptr;
  ollama_timing_ = nullptr;
  ollama_clear_timing_ = nullptr;
  ollama_foreground_ = nullptr;
  ollama_block_ = nullptr;
  ollama_shutdown_ = nullptr;
  return false;
}

void NeuraEngineSession::Background() {
  if (foreground_) foreground_(0);
  if (ollama_foreground_) ollama_foreground_(0);
}

NeuraEngineSession::~NeuraEngineSession() {
  channel_->SetMethodCallHandler(nullptr);
  if (stop_) stop_();
  if (ollama_shutdown_) ollama_shutdown_();
  if (library_) FreeLibrary(library_);
}


