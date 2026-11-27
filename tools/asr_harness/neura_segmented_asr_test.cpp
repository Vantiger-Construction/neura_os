#include "../../windows/runner/neura_segmented_asr.h"

#include <atomic>
#include <condition_variable>
#include <functional>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <vector>

// Standalone checks for the multilingual (VAD + whole-phrase) pipeline used by
// the Windows Whisper profile. No model, microphone, SDK or network.

namespace {

using namespace std::chrono_literals;

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Speech is any window whose first sample is non-zero; a phrase ends after
// two silent windows, like a VAD's minimum silence.
class FakeSegmenter : public neura::SpeechSegmenter {
 public:
  size_t WindowSize() const override { return 4; }
  void Accept(const float* samples) override {
    if (samples[0] != 0.0f) {
      current_.insert(current_.end(), samples, samples + 4);
      silent_ = 0;
    } else if (!current_.empty() && ++silent_ >= 2) {
      Close();
    }
  }
  void Flush() override {
    ++flushed;
    if (!current_.empty()) Close();
  }
  bool Empty() override { return ready_.empty(); }
  std::vector<float> PopFront() override {
    auto front = std::move(ready_.front());
    ready_.pop_front();
    return front;
  }
  void Reset() override {
    current_.clear();
    ready_.clear();
    silent_ = 0;
  }
  int flushed = 0;

 private:
  void Close() {
    ready_.push_back(std::move(current_));
    current_.clear();
    silent_ = 0;
  }
  std::vector<float> current_;
  std::deque<std::vector<float>> ready_;
  int silent_ = 0;
};

class FakeDecoder : public neura::SegmentDecoder {
 public:
  std::chrono::milliseconds delay{0};
  bool block = false;
  bool throw_once = false;
  std::string language = "<|es|>";
  std::atomic<int> decoded{0};
  std::atomic<int> entered{0};
  std::mutex mutex;
  std::condition_variable changed;
  bool released = false;

  neura::AsrResult Decode(const std::vector<float>& samples) override {
    ++entered;
    {
      std::unique_lock<std::mutex> lock(mutex);
      changed.notify_all();
      if (block) changed.wait(lock, [&] { return released; });
    }
    if (delay.count() > 0) std::this_thread::sleep_for(delay);
    if (throw_once) {
      throw_once = false;
      throw std::runtime_error("synthetic private decoder error");
    }
    const int n = ++decoded;
    neura::AsrResult result;
    result.text = "  frase   " + std::to_string(n) + " (" +
                  std::to_string(samples.size()) + ")\n";
    result.language = language;
    return result;
  }
  void WaitEntered(int count) {
    std::unique_lock<std::mutex> lock(mutex);
    Require(changed.wait_for(lock, 2s, [&] { return entered >= count; }),
            "Decoder was not reached");
  }
  void Release() {
    std::lock_guard<std::mutex> lock(mutex);
    released = true;
    changed.notify_all();
  }
};

// Mirrors the Windows Whisper profile: capture callbacks feed the session;
// every decoder-side call goes straight to the SegmentedRecognizer.
class PipelineBackend : public neura::AsrBackend {
 public:
  PipelineBackend(neura::SpeechSegmenter& segmenter,
                  neura::SegmentDecoder& decoder,
                  std::chrono::milliseconds timeout = 2s)
      : recognizer(segmenter, decoder, timeout) {}

  bool CreateStream() override {
    recognizer.Begin();
    return true;
  }
  bool OpenInput(Capture callback, void* context) override {
    capture = callback;
    capture_context = context;
    return true;
  }
  bool StartInput() override { return true; }
  void CloseInput() noexcept override { ++closed; }
  void DestroyStream() noexcept override { recognizer.End(); }
  void Accept(const float* samples, size_t count) override {
    recognizer.Accept(samples, count);
  }
  bool IsReady() override { return recognizer.IsReady(); }
  void Decode() override { recognizer.QueueNext(); }
  neura::AsrResult Result() override { return recognizer.Result(); }
  void Reset() override {}
  void FinishInput() override { recognizer.FinishInput(); }

  // One phrase: `speech` windows of voice, then three silent windows.
  bool Say(int speech = 3) {
    std::vector<float> audio;
    for (int i = 0; i < speech; ++i) audio.insert(audio.end(), 4, 0.5f);
    audio.insert(audio.end(), 12, 0.0f);
    return capture(audio.data(), audio.size(), capture_context);
  }
  // A live microphone keeps delivering audio, silence included.
  bool Silence() {
    std::vector<float> audio(4, 0.0f);
    return capture(audio.data(), audio.size(), capture_context);
  }
  bool Speak(int speech) {
    std::vector<float> audio(static_cast<size_t>(speech) * 4, 0.5f);
    return capture(audio.data(), audio.size(), capture_context);
  }

  neura::SegmentedRecognizer recognizer;
  Capture capture = nullptr;
  void* capture_context = nullptr;
  std::atomic<int> closed{0};
};

struct Segments {
  std::mutex mutex;
  std::condition_variable changed;
  struct Entry {
    std::string text;
    std::string language;
    bool final;
  };
  std::vector<Entry> entries;

  static void Receive(std::string text, std::string language, bool final,
                      uint64_t, void* context) {
    auto& self = *static_cast<Segments*>(context);
    std::lock_guard<std::mutex> lock(self.mutex);
    self.entries.push_back({std::move(text), std::move(language), final});
    self.changed.notify_all();
  }
  size_t Count() {
    std::lock_guard<std::mutex> lock(mutex);
    return entries.size();
  }
  void Wait(size_t count, PipelineBackend& backend) {
    for (int i = 0; i < 600 && Count() < count; ++i) {
      backend.Silence();
      std::this_thread::sleep_for(5ms);
    }
    Require(Count() >= count, "Timed out waiting for a phrase");
  }
};

void LanguageCodes() {
  using R = neura::SegmentedRecognizer;
  Require(R::LanguageCode("<|es|>") == "es", "Whisper token not normalized");
  Require(R::LanguageCode("DE") == "de", "Upper case not normalized");
  Require(R::LanguageCode("fr") == "fr", "Plain code changed");
  Require(R::LanguageCode("e s").empty(), "Space accepted in a code");
  Require(R::LanguageCode("es\"}").empty(), "Punctuation accepted in a code");
  Require(R::LanguageCode("abcdefghij").empty(), "Overlong code accepted");
}

void SlowModelDoesNotStallCapture() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  decoder.delay = 60ms;
  PipelineBackend backend(segmenter, decoder);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(1), "Start failed");
  for (int i = 0; i < 3; ++i) Require(backend.Say(), "Capture was refused");
  segments.Wait(1, backend);
  session.Stop(true);
  Require(segments.entries[0].final, "A decoded phrase was not final");
  Require(segments.entries[0].language == "es",
          "Detected language was not delivered");
  Require(segments.entries[0].text.rfind("frase 1 (12)", 0) == 0,
          "Phrase text was not cleaned or was cut");
}

void ExplicitStopReturnsQueuedPhrases() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  decoder.delay = 30ms;
  PipelineBackend backend(segmenter, decoder);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(2), "Start failed");
  backend.Say();
  backend.Say();
  backend.Speak(2);  // still talking when the person taps stop
  const auto text = session.Stop(false);
  Require(segmenter.flushed == 1, "Stop did not flush the speech detector");
  Require(decoder.decoded == 3, "Stop did not decode every queued phrase");
  Require(text == "frase 1 (12) frase 2 (12) frase 3 (8)",
          "Stop lost, reordered or duplicated phrases");
}

void SafeStopDiscardsInFlight() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  decoder.block = true;
  PipelineBackend backend(segmenter, decoder);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(3), "Start failed");
  backend.Say();
  backend.Say();
  decoder.WaitEntered(1);
  std::atomic<bool> returned{false};
  std::string result;
  std::thread stopping([&] {
    result = session.Stop(true);
    returned = true;
  });
  std::this_thread::sleep_for(50ms);
  const bool waited_for_model = !returned.load();
  decoder.Release();
  stopping.join();
  Require(waited_for_model, "Stop returned while the model still ran");
  Require(result.empty() && segments.Count() == 0,
          "Safe stop disclosed phrase text");
  Require(decoder.entered == 1, "Queued phrase was decoded after Safe Mode");
}

void BacklogFailsClosed() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  decoder.block = true;
  PipelineBackend backend(segmenter, decoder);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(4), "Start failed");
  backend.Say();
  decoder.WaitEntered(1);
  bool refused = false;
  for (int i = 0; i < 40 && !refused; ++i) {
    refused = !backend.Say();
    std::this_thread::sleep_for(2ms);
  }
  Require(refused, "An unbounded phrase backlog was accepted");
  decoder.Release();
  Require(session.Stop(false).empty(), "Backlog failure returned text");
}

void DecoderErrorFailsClosed() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  decoder.throw_once = true;
  PipelineBackend backend(segmenter, decoder);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(5), "Start failed");
  backend.Say();
  decoder.WaitEntered(1);
  bool refused = false;
  for (int i = 0; i < 200 && !refused; ++i) {
    refused = !backend.Say();
    std::this_thread::sleep_for(5ms);
  }
  Require(refused, "Capture continued after a model error");
  Require(session.Stop(false).empty() && segments.Count() == 0,
          "Model error disclosed text");
}

void FinishTimeoutFailsClosed() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  decoder.block = true;
  PipelineBackend backend(segmenter, decoder, 100ms);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(6), "Start failed");
  backend.Say();
  decoder.WaitEntered(1);
  std::thread release([&] {
    std::this_thread::sleep_for(300ms);
    decoder.Release();
  });
  const auto text = session.Stop(false);
  release.join();
  Require(text.empty(), "A stop that timed out returned partial text");
}

void RestartForgetsOldPhrases() {
  FakeSegmenter segmenter;
  FakeDecoder decoder;
  PipelineBackend backend(segmenter, decoder);
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(7), "Start failed");
  backend.Speak(3);  // unfinished phrase, then a discarding stop
  session.Stop(true);
  Require(session.Start(8), "Restart failed");
  backend.Say(1);
  const auto text = session.Stop(false);
  Require(text == "frase 1 (4)", "Audio from the earlier turn leaked");
}

}  // namespace

int main() {
  try {
    const std::vector<std::pair<const char*, std::function<void()>>> tests{
        {"language codes are normalized", LanguageCodes},
        {"slow model does not stall capture", SlowModelDoesNotStallCapture},
        {"explicit stop returns queued phrases",
         ExplicitStopReturnsQueuedPhrases},
        {"Safe Mode stop discards in-flight phrase", SafeStopDiscardsInFlight},
        {"phrase backlog fails closed", BacklogFailsClosed},
        {"decoder error fails closed", DecoderErrorFailsClosed},
        {"finish timeout fails closed", FinishTimeoutFailsClosed},
        {"restart forgets old phrases", RestartForgetsOldPhrases},
    };
    for (const auto& [name, test] : tests) {
      test();
      std::cout << "PASS " << name << '\n';
    }
    std::cout << tests.size() << " multilingual ASR pipeline checks passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
