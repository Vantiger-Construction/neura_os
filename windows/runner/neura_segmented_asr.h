#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "neura_asr_session.h"

namespace neura {

// Voice activity detection over 16 kHz mono audio. Production wraps the
// Sherpa-ONNX Silero VAD; the standalone harness substitutes a fake.
// Every call happens on the AsrSession decoder worker.
class SpeechSegmenter {
 public:
  virtual ~SpeechSegmenter() = default;
  virtual size_t WindowSize() const = 0;
  // Exactly WindowSize() samples.
  virtual void Accept(const float* samples) = 0;
  virtual void Flush() = 0;
  virtual bool Empty() = 0;
  // Removes and returns the oldest finished speech segment.
  virtual std::vector<float> PopFront() = 0;
  virtual void Reset() = 0;
};

// Whole-utterance recognition, such as multilingual Whisper. Called only on
// the pipeline's own decode thread, one segment at a time.
class SegmentDecoder {
 public:
  virtual ~SegmentDecoder() = default;
  // Returns the text and, when the model identifies it, the language.
  virtual AsrResult Decode(const std::vector<float>& samples) = 0;
};

// Splits live audio into spoken phrases and decodes each phrase on a separate
// thread, so a slow whole-utterance model never stalls the capture queue.
//
// It implements the decoder-worker half of AsrBackend: the session worker
// feeds audio and collects text; one private thread runs the model. Pending
// phrases are bounded; falling further behind fails closed.
class SegmentedRecognizer {
 public:
  static constexpr size_t kMaxPendingSegments = 6;
  // Longest audio one phrase may carry into the decoder: 30 s at 16 kHz.
  static constexpr size_t kMaxSegmentSamples = 16000 * 30;

  SegmentedRecognizer(SpeechSegmenter& segmenter, SegmentDecoder& decoder,
                      std::chrono::milliseconds finish_timeout =
                          std::chrono::seconds(8))
      : segmenter_(segmenter),
        decoder_(decoder),
        finish_timeout_(finish_timeout) {}
  ~SegmentedRecognizer() { End(); }
  SegmentedRecognizer(const SegmentedRecognizer&) = delete;
  SegmentedRecognizer& operator=(const SegmentedRecognizer&) = delete;

  // Called from AsrBackend::CreateStream (control thread, before capture).
  void Begin() {
    End();
    segmenter_.Reset();
    window_.clear();
    window_.reserve(segmenter_.WindowSize());
    finishing_ = false;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      queue_.clear();
      results_.clear();
      busy_ = false;
      cancelled_ = false;
      failed_ = false;
    }
    worker_ = std::thread(&SegmentedRecognizer::Run, this);
  }

  // Called from AsrBackend::DestroyStream: cancels queued phrases, waits for
  // a phrase already inside the model, and discards every result.
  void End() noexcept {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      cancelled_ = true;
      queue_.clear();
      results_.clear();
    }
    changed_.notify_all();
    if (worker_.joinable()) worker_.join();
    window_.clear();
  }

  // --- Session decoder worker only -------------------------------------
  void Accept(const float* samples, size_t count) {
    const size_t window = segmenter_.WindowSize();
    for (size_t i = 0; i < count; ++i) {
      window_.push_back(samples[i]);
      if (window_.size() == window) {
        segmenter_.Accept(window_.data());
        window_.clear();
      }
    }
  }

  bool IsReady() { return !segmenter_.Empty(); }

  // Hands one finished phrase to the decode thread.
  void QueueNext() {
    if (segmenter_.Empty()) return;
    auto samples = segmenter_.PopFront();
    if (samples.empty()) return;
    if (samples.size() > kMaxSegmentSamples) samples.resize(kMaxSegmentSamples);
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (cancelled_) return;
      if (queue_.size() >= kMaxPendingSegments) {
        failed_ = true;
        return;
      }
      queue_.push_back(std::move(samples));
    }
    changed_.notify_all();
  }

  void FinishInput() {
    if (!window_.empty()) {
      window_.resize(segmenter_.WindowSize(), 0.0f);
      segmenter_.Accept(window_.data());
      window_.clear();
    }
    segmenter_.Flush();
    finishing_ = true;
  }

  // Joins every decoded phrase that is ready. While finishing, first waits
  // (bounded) for queued phrases so the explicit stop returns all the text.
  AsrResult Result() {
    std::unique_lock<std::mutex> lock(mutex_);
    if (finishing_) {
      const bool drained = changed_.wait_for(lock, finish_timeout_, [&] {
        return cancelled_ || failed_ || (queue_.empty() && !busy_);
      });
      if (!drained) failed_ = true;
    }
    if (failed_) {
      results_.clear();
      return {{}, false, {}, true};
    }
    AsrResult joined;
    for (auto& result : results_) {
      if (result.text.empty()) continue;
      if (!joined.text.empty()) joined.text += ' ';
      joined.text += result.text;
      if (!result.language.empty()) joined.language = result.language;
    }
    results_.clear();
    joined.endpoint = !joined.text.empty();
    return joined;
  }

 private:
  void Run() noexcept {
    for (;;) {
      std::vector<float> samples;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        changed_.wait(lock, [&] { return cancelled_ || !queue_.empty(); });
        if (cancelled_) return;
        samples = std::move(queue_.front());
        queue_.pop_front();
        busy_ = true;
      }
      AsrResult result;
      bool ok = true;
      try {
        result = decoder_.Decode(samples);
      } catch (...) {
        ok = false;  // Never propagate a model error that may contain text.
      }
      std::fill(samples.begin(), samples.end(), 0.0f);
      {
        std::lock_guard<std::mutex> lock(mutex_);
        busy_ = false;
        if (!ok || result.failed) {
          failed_ = true;
        } else if (!cancelled_) {
          results_.push_back(Clean(std::move(result)));
        }
      }
      changed_.notify_all();
    }
  }

  static AsrResult Clean(AsrResult result) {
    std::string text;
    text.reserve(result.text.size());
    bool space = false;
    for (const char c : result.text) {
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        space = !text.empty();
        continue;
      }
      if (space) text += ' ';
      space = false;
      text += c;
    }
    result.text = std::move(text);
    result.language = LanguageCode(result.language);
    result.endpoint = true;
    return result;
  }

 public:
  // "<|es|>", "ES" or "es" become "es"; anything else becomes empty.
  static std::string LanguageCode(const std::string& raw) {
    std::string code;
    for (const char c : raw) {
      if (c >= 'A' && c <= 'Z') {
        code += static_cast<char>(c - 'A' + 'a');
      } else if (c >= 'a' && c <= 'z') {
        code += c;
      } else if (c != '<' && c != '>' && c != '|') {
        return {};
      }
      if (code.size() > 8) return {};
    }
    return code;
  }

 private:
  SpeechSegmenter& segmenter_;
  SegmentDecoder& decoder_;
  const std::chrono::milliseconds finish_timeout_;
  std::vector<float> window_;
  bool finishing_ = false;

  std::mutex mutex_;
  std::condition_variable changed_;
  std::deque<std::vector<float>> queue_;
  std::vector<AsrResult> results_;
  bool busy_ = false;
  bool cancelled_ = false;
  bool failed_ = false;
  std::thread worker_;
};

}  // namespace neura
