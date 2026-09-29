#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <string>
#include <thread>
#include <utility>

namespace neura {

// One producer (audio callback), one consumer (decoder). No allocation, locks,
// feature extraction, or I/O on the audio thread. Two seconds of 16 kHz audio.
class AsrAudioQueue {
 public:
  static constexpr size_t kCapacity = 32000;
  static_assert(std::atomic<size_t>::is_always_lock_free);

  bool Push(const float* input, size_t count) noexcept {
    const auto write = write_.load(std::memory_order_relaxed);
    const auto read = read_.load(std::memory_order_acquire);
    if (count > kCapacity - (write - read)) return false;
    for (size_t i = 0; i < count; ++i) {
      samples_[(write + i) % kCapacity] = input == nullptr ? 0 : input[i];
    }
    write_.store(write + count, std::memory_order_release);
    return true;
  }

  size_t Pop(float* output, size_t capacity) noexcept {
    const auto read = read_.load(std::memory_order_relaxed);
    const auto write = write_.load(std::memory_order_acquire);
    const auto count = std::min(capacity, write - read);
    for (size_t i = 0; i < count; ++i) {
      auto& sample = samples_[(read + i) % kCapacity];
      output[i] = sample;
      sample = 0;
    }
    read_.store(read + count, std::memory_order_release);
    return count;
  }

  // Caller must first stop the producer and join the consumer.
  void Clear() noexcept {
    samples_.fill(0);
    read_.store(0);
    write_.store(0);
  }

 private:
  std::array<float, kCapacity> samples_{};
  std::atomic<size_t> read_{0};
  std::atomic<size_t> write_{0};
};

struct AsrResult {
  std::string text;
  bool endpoint = false;
};

// Production implements this with local Sherpa/PortAudio calls. The standalone
// harness substitutes deterministic devices/decoding, without a model or mic.
class AsrBackend {
 public:
  using Capture = bool (*)(const float*, size_t, void*);
  virtual ~AsrBackend() = default;
  virtual bool CreateStream() = 0;
  virtual bool OpenInput(Capture capture, void* context) = 0;
  virtual bool StartInput() = 0;
  virtual void CloseInput() noexcept = 0;  // joins all audio callbacks
  virtual void DestroyStream() noexcept = 0;
  // These functions run exclusively on the decoder worker.
  virtual void Accept(const float* samples, size_t count) = 0;
  virtual bool IsReady() = 0;
  virtual void Decode() = 0;
  virtual AsrResult Result() = 0;
  virtual void Reset() = 0;
  virtual void FinishInput() = 0;
};

// Start/Stop are serialized by the Flutter window thread. Safe Mode uses
// Stop(true): close capture, cancel further decoding, join, and discard text.
class AsrSession {
 public:
  using Segment = void (*)(std::string, bool, uint64_t, void*);

  AsrSession(AsrBackend& backend, Segment segment, void* context)
      : backend_(backend), segment_(segment), context_(context) {}
  ~AsrSession() { Stop(true); }
  AsrSession(const AsrSession&) = delete;
  AsrSession& operator=(const AsrSession&) = delete;

  bool Start(uint64_t generation) {
    if (active_) return accepting_.load();
    generation_ = generation;
    failed_.store(false);
    discard_.store(true);
    cancelled_.store(false);
    active_ = true;
    try {
      if (!backend_.CreateStream() || !backend_.OpenInput(&Capture, this)) {
        Stop(true);
        return false;
      }
      accepting_.store(true);
      worker_ = std::thread(&AsrSession::Run, this);
      if (!backend_.StartInput()) {
        Stop(true);
        return false;
      }
      return true;
    } catch (...) {
      Stop(true);
      return false;  // Never propagate a model/audio error containing text.
    }
  }

  std::string Stop(bool discard) {
    if (!active_) return {};
    accepting_.store(false);
    discard_.store(discard);
    if (discard) cancelled_.store(true);
    backend_.CloseInput();
    cancelled_.store(true);
    if (worker_.joinable()) worker_.join();
    backend_.DestroyStream();
    audio_.Clear();
    active_ = false;
    std::string result;
    if (!discard && !failed_.load()) result.swap(transcript_);
    transcript_.clear();
    partial_.clear();
    return result;
  }

 private:
  static bool Capture(const float* input, size_t count, void* context) {
    auto* self = static_cast<AsrSession*>(context);
    if (!self->accepting_.load()) return false;
    if (!self->audio_.Push(input, count)) {
      // Backpressure ends capture instead of accumulating unbounded audio or
      // silently presenting a transcript with missing chunks as complete.
      self->failed_.store(true);
      self->accepting_.store(false);
      return false;
    }
    return true;
  }

  void ReadResult(bool finishing) {
    auto result = backend_.Result();
    if (result.text.size() > 16384 ||
        result.text.find('\0') != std::string::npos ||
        result.text.find('\x7f') != std::string::npos) {
      failed_.store(true);
      return;
    }
    if (!result.text.empty()) {
      if (result.endpoint || finishing) {
        if (transcript_.size() + result.text.size() + 1 > 65536) {
          failed_.store(true);
          return;
        }
        if (!transcript_.empty()) transcript_ += ' ';
        transcript_ += result.text;
        partial_.clear();
        if (!cancelled_.load()) {
          segment_(std::move(result.text), true, generation_, context_);
        }
      } else if (result.text != partial_ && !cancelled_.load()) {
        partial_ = result.text;
        segment_(std::move(result.text), false, generation_, context_);
      }
    }
    if (result.endpoint) {
      backend_.Reset();
      partial_.clear();
    }
  }

  void DecodeReady(bool finishing) {
    while (!failed_.load() && (finishing || !cancelled_.load()) &&
           backend_.IsReady()) {
      backend_.Decode();
    }
    if (!failed_.load() && (finishing || !cancelled_.load())) {
      ReadResult(finishing);
    }
  }

  void Run() noexcept {
    std::array<float, 1600> samples{};
    try {
      while (!cancelled_.load() && !failed_.load()) {
        const auto count = audio_.Pop(samples.data(), samples.size());
        if (count != 0) {
          backend_.Accept(samples.data(), count);
          samples.fill(0);
          DecodeReady(false);
        } else {
          std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
      }
      // Only an ordinary explicit stop flushes the bounded tail. Safe Mode,
      // disposal, failures, and overflow never perform more inference here.
      if (!discard_.load() && !failed_.load()) {
        size_t count;
        while ((count = audio_.Pop(samples.data(), samples.size())) != 0) {
          backend_.Accept(samples.data(), count);
          samples.fill(0);
        }
        backend_.FinishInput();
        DecodeReady(true);
      }
    } catch (...) {
      failed_.store(true);
    }
    accepting_.store(false);
    samples.fill(0);
  }

  AsrBackend& backend_;
  Segment segment_;
  void* context_;
  AsrAudioQueue audio_;
  std::thread worker_;
  std::atomic<bool> accepting_{false};
  std::atomic<bool> cancelled_{true};
  std::atomic<bool> discard_{true};
  std::atomic<bool> failed_{false};
  bool active_ = false;
  uint64_t generation_ = 0;
  std::string transcript_;
  std::string partial_;
};

}  // namespace neura
