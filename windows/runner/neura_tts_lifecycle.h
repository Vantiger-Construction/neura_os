#pragma once

#include <cstdint>
#include <string>

// No Windows, audio, threads, pointers or user text in lifecycle ownership.
// The real owner uses a fresh event queue per request plus its SAPI stream
// number. SAPI may reuse stream 1, so a stream number alone is insufficient.
class NeuraTtsLifecycle {
 public:
  bool CanStart(int64_t request) const {
    return !failed_ && state_ != "speaking" && request > request_;
  }
  bool Start(int64_t request, uint32_t stream) {
    if (!CanStart(request) || stream == 0) return false;
    request_ = request;
    stream_ = stream;
    state_ = "speaking";
    return true;
  }
  void Cancel() {
    stream_ = 0;
    if (!failed_ && request_ != 0) state_ = "cancelled";
  }
  void End(int64_t owner, uint32_t stream) {
    if (state_ == "speaking" && owner == request_ && stream_ != 0 && stream == stream_) {
      state_ = "completed";
      stream_ = 0;
    }
  }
  // True only for events from the active utterance's own SAPI stream.
  bool Owns(uint32_t stream) const {
    return state_ == "speaking" && stream_ != 0 && stream == stream_;
  }
  void Fail() {
    failed_ = true;
    stream_ = 0;
    state_ = "failed";
  }
  int64_t request() const { return request_; }
  const std::string& state() const { return state_; }

 private:
  int64_t request_ = 0;
  uint32_t stream_ = 0;
  std::string state_ = "idle";
  bool failed_ = false;
};

inline std::wstring NeuraTtsPitchText(const std::wstring& text, int pitch) {
  std::wstring result = L"<pitch absmiddle=\"" + std::to_wstring(pitch) + L"\">";
  for (wchar_t c : text) {
    switch (c) {
      case L'&': result += L"&amp;"; break;
      case L'<': result += L"&lt;"; break;
      case L'>': result += L"&gt;"; break;
      case L'\"': result += L"&quot;"; break;
      case L'\'': result += L"&apos;"; break;
      default: result += c; break;
    }
  }
  return result + L"</pitch>";
}
