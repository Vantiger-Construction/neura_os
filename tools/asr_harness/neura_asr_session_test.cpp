#include "../../windows/runner/neura_asr_session.h"

#include <condition_variable>
#include <functional>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <vector>

#if defined(__linux__)
#include <cerrno>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#endif

namespace {

using namespace std::chrono_literals;

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// Deny network creation in this process and its worker threads. Windows device
// evidence is separate; this exercises the shared production session on Linux.
void DenyNetwork() {
#if defined(__linux__)
  sock_filter filters[] = {
      BPF_STMT(BPF_LD | BPF_W | BPF_ABS,
               static_cast<unsigned int>(offsetof(seccomp_data, nr))),
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socket, 2, 0),
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socketpair, 1, 0),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
  };
  sock_fprog program{static_cast<unsigned short>(std::size(filters)), filters};
  Require(prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0,
          "Cannot enable no-new-privileges for offline test");
  Require(prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) == 0,
          "Cannot install network-deny filter");
  Require(socket(AF_INET, SOCK_STREAM, 0) == -1 && errno == EPERM,
          "Network access was not denied");
  std::cout << "Network socket creation denied for harness and workers\n";
#endif
}

struct Segments {
  std::mutex mutex;
  std::condition_variable changed;
  struct Entry { std::string text; bool final; uint64_t generation; };
  std::vector<Entry> entries;

  static void Receive(std::string text, bool final, uint64_t generation,
                      void* context) {
    auto& self = *static_cast<Segments*>(context);
    std::lock_guard<std::mutex> lock(self.mutex);
    self.entries.push_back({std::move(text), final, generation});
    self.changed.notify_all();
  }

  void Wait(size_t count) {
    std::unique_lock<std::mutex> lock(mutex);
    Require(changed.wait_for(lock, 2s, [&] { return entries.size() >= count; }),
            "Timed out waiting for a segment");
  }
};

class FakeBackend : public neura::AsrBackend {
 public:
  bool fail_create = false;
  bool fail_open = false;
  bool fail_start = false;
  bool throw_decode = false;
  bool block_decode = false;
  bool endpoint = true;
  std::atomic<int> created{0}, opened{0}, closed{0}, destroyed{0};
  std::atomic<int> accepted{0}, decoded{0}, finished{0};
  std::mutex mutex;
  std::condition_variable changed;
  bool release_decode = false;
  bool entered_decode = false;
  bool stream_exists = false;
  Capture capture = nullptr;
  void* capture_context = nullptr;

  bool CreateStream() override {
    ++created;
    stream_exists = !fail_create;
    return stream_exists;
  }
  bool OpenInput(Capture callback, void* context) override {
    ++opened;
    capture = callback;
    capture_context = context;
    return !fail_open;
  }
  bool StartInput() override { return !fail_start; }
  void CloseInput() noexcept override {
    ++closed;
    changed.notify_all();
  }
  void DestroyStream() noexcept override {
    if (stream_exists) {
      ++destroyed;
      stream_exists = false;
    }
    worker_id_ = {};
    pending_ = false;
    text_.clear();
  }
  bool Audio(size_t count = 320) {
    std::array<float, neura::AsrAudioQueue::kCapacity + 1> audio{};
    audio.fill(0.25f);
    return capture(audio.data(), count, capture_context);
  }
  void CheckWorker() {
    const auto current = std::this_thread::get_id();
    Require(current != creator_, "Decoder ran on the capture/control thread");
    if (worker_id_ == std::thread::id{}) worker_id_ = current;
    Require(current == worker_id_, "Decoder was accessed from multiple threads");
  }
  void Accept(const float*, size_t) override {
    CheckWorker();
    ++accepted;
    pending_ = true;
  }
  bool IsReady() override {
    CheckWorker();
    return pending_;
  }
  void Decode() override {
    CheckWorker();
    {
      std::unique_lock<std::mutex> lock(mutex);
      entered_decode = true;
      changed.notify_all();
      if (block_decode) changed.wait(lock, [&] { return release_decode; });
    }
    if (throw_decode) throw std::runtime_error("synthetic private decoder error");
    ++decoded;
    pending_ = false;
    text_ = "synthetic private phrase";
  }
  neura::AsrResult Result() override {
    CheckWorker();
    return {text_, endpoint};
  }
  void Reset() override { CheckWorker(); text_.clear(); }
  void FinishInput() override { CheckWorker(); ++finished; }

  void WaitForDecode() {
    std::unique_lock<std::mutex> lock(mutex);
    Require(changed.wait_for(lock, 2s, [&] { return entered_decode; }),
            "Decoder did not start");
  }
  void Release() {
    std::lock_guard<std::mutex> lock(mutex);
    release_decode = true;
    changed.notify_all();
  }

 private:
  const std::thread::id creator_ = std::this_thread::get_id();
  std::thread::id worker_id_;
  bool pending_ = false;
  std::string text_;
};

void QueueBoundsAndWrap() {
  neura::AsrAudioQueue queue;
  std::vector<float> input(neura::AsrAudioQueue::kCapacity, 0.5f);
  std::vector<float> output(input.size());
  Require(queue.Push(input.data(), input.size()), "Initial bounded push failed");
  Require(!queue.Push(input.data(), 1), "Overflow was accepted");
  Require(queue.Pop(output.data(), 15999) == 15999, "Partial pop failed");
  Require(queue.Push(input.data(), 15999), "Wrapped push failed");
  Require(queue.Pop(output.data(), output.size()) == output.size(),
          "Wrapped pop failed");
  Require(output == input, "Audio order/content changed at wrap");
  queue.Clear();
  Require(queue.Pop(output.data(), 1) == 0, "Clear retained audio");
  Require(queue.Push(nullptr, 1), "Missing input was not handled");
  Require(queue.Pop(output.data(), 1) == 1 && output[0] == 0,
          "Missing input must become silence");
}

void QueueConcurrentOrder() {
  neura::AsrAudioQueue queue;
  constexpr int count = 200000;
  std::thread producer([&] {
    for (int i = 0; i < count; ++i) {
      const float value = static_cast<float>(i);
      while (!queue.Push(&value, 1)) std::this_thread::yield();
    }
  });
  bool ordered = true;
  for (int i = 0; i < count; ++i) {
    float value = -1;
    while (queue.Pop(&value, 1) == 0) std::this_thread::yield();
    ordered = ordered && value == static_cast<float>(i);
  }
  producer.join();
  Require(ordered, "Concurrent audio order was corrupted");
}

void StartupFailure(int stage) {
  FakeBackend backend;
  backend.fail_create = stage == 0;
  backend.fail_open = stage == 1;
  backend.fail_start = stage == 2;
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(!session.Start(1), "Failed device unexpectedly started");
  Require(backend.closed == 1, "Failed startup did not close capture");
  Require(backend.destroyed == (stage == 0 ? 0 : 1), "Stream was leaked");
  Require(session.Stop(true).empty(), "Failed start retained a transcript");
  Require(backend.finished == 0, "Failed start flushed inference");
  backend.fail_create = backend.fail_open = backend.fail_start = false;
  Require(session.Start(2), "Retry after failure could not start");
  session.Stop(true);
}

void PartialFinalAndRestart() {
  FakeBackend backend;
  backend.endpoint = false;
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(7), "Start failed");
  Require(session.Start(7) && backend.created == 1, "Start opened two mics");
  Require(backend.Audio(), "Capture refused audio");
  segments.Wait(1);
  Require(session.Stop(false) == "synthetic private phrase", "Stop lost partial");
  Require(backend.finished == 1, "Normal stop did not flush bounded tail");
  Require(!backend.Audio(), "Late audio survived stop");
  Require(segments.entries.size() == 1 && !segments.entries[0].final &&
              segments.entries[0].generation == 7,
          "Partial segment/generation mismatch");
  backend.endpoint = true;
  Require(session.Start(8), "Restart failed");
  backend.Audio();
  segments.Wait(2);
  Require(session.Stop(false) == "synthetic private phrase",
          "Restart leaked old transcript or duplicated final");
  Require(segments.entries[1].final && segments.entries[1].generation == 8,
          "Final segment/generation mismatch");
  Require(session.Stop(false).empty(), "Repeated stop returned old transcript");
  Require(backend.closed == 2 && backend.destroyed == 2, "Session leaked");
}

void SafeStopJoinsAndDiscards() {
  FakeBackend backend;
  backend.block_decode = true;
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(1), "Start failed");
  backend.Audio();
  backend.WaitForDecode();
  backend.Audio();  // backlog must be discarded, not decoded after cancellation
  std::atomic<bool> returned{false};
  std::string result;
  std::thread stopping([&] { result = session.Stop(true); returned = true; });
  bool closed;
  {
    std::unique_lock<std::mutex> lock(backend.mutex);
    closed = backend.changed.wait_for(lock, 2s, [&] { return backend.closed == 1; });
  }
  const bool joined_before_return = !returned.load();
  backend.Release();
  stopping.join();
  Require(closed && joined_before_return, "Stop did not close audio and join");
  Require(result.empty() && segments.entries.empty(), "Safe stop disclosed text");
  Require(backend.accepted == 1 && backend.finished == 0,
          "Safe stop decoded backlog or flushed new inference");
  Require(backend.destroyed == 1 && !backend.Audio(), "Mic/stream survived stop");
}

void OverflowFailsClosed() {
  FakeBackend backend;
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(1), "Start failed");
  Require(!backend.Audio(neura::AsrAudioQueue::kCapacity + 1),
          "Overflow did not end capture");
  Require(session.Stop(false).empty(), "Overflow returned incomplete transcript");
  Require(backend.finished == 0 && !backend.Audio(), "Overflow resumed capture");
}

void DecoderExceptionAndDisposal() {
  FakeBackend backend;
  backend.throw_decode = true;
  Segments segments;
  {
    neura::AsrSession session(backend, &Segments::Receive, &segments);
    Require(session.Start(1), "Start failed");
    backend.Audio();
    backend.WaitForDecode();
    // Destruction must join even if decoding throws concurrently.
  }
  Require(backend.closed == 1 && backend.destroyed == 1,
          "Exception/disposal leaked capture or stream");
  Require(segments.entries.empty() && backend.finished == 0,
          "Exception/disposal emitted private text");
}

void BenchmarkCallerDiscards() {
  FakeBackend backend;
  Segments segments;
  neura::AsrSession session(backend, &Segments::Receive, &segments);
  Require(session.Start(1), "Start failed");
  backend.Audio();
  segments.Wait(1);
  session.Stop(false);  // Like Dart's harness: ignore the normal stop return.
  Require(session.Stop(false).empty(), "Benchmark transcript was retained");
  Require(backend.destroyed == 1 && backend.closed == 1, "Benchmark leaked mic");
}

}  // namespace

int main() {
  try {
    DenyNetwork();
    const std::vector<std::pair<const char*, std::function<void()>>> tests{
        {"bounded queue, wrap, clear, silence", QueueBoundsAndWrap},
        {"concurrent audio order", QueueConcurrentOrder},
        {"stream creation failure", [] { StartupFailure(0); }},
        {"audio open failure", [] { StartupFailure(1); }},
        {"audio start failure", [] { StartupFailure(2); }},
        {"partial/final, idempotence, restart", PartialFinalAndRestart},
        {"Safe Mode close/join/discard", SafeStopJoinsAndDiscards},
        {"overflow fails closed", OverflowFailsClosed},
        {"decoder exception and disposal", DecoderExceptionAndDisposal},
        {"benchmark caller discards stop text", BenchmarkCallerDiscards},
    };
    for (const auto& [name, test] : tests) {
      test();
      std::cout << "PASS " << name << '\n';
    }
    std::cout << tests.size() << " offline ASR session checks passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
