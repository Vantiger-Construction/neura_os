#include "neura_on_device_asr.h"

#include <atomic>
#include <chrono>
#include <filesystem>
#include <string>
#include <system_error>
#include <thread>
#include <utility>

#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
#include <portaudio.h>
#include <sherpa-onnx/c-api/c-api.h>
#endif

namespace {

constexpr wchar_t kRuntimeOptIn[] = L"NEURA_ON_DEVICE_ASR_ENABLE";
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
constexpr wchar_t kModelDirectory[] = L"NEURA_ON_DEVICE_ASR_MODEL_DIR";
#endif

std::wstring ReadEnvironment(const wchar_t* name) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required == 0) {
    return {};
  }

  std::wstring value(required, L'\0');
  const DWORD written = GetEnvironmentVariableW(name, value.data(), required);
  if (written == 0 || written >= required) {
    return {};
  }
  value.resize(written);
  return value;
}

bool RuntimeOptedIn() {
  return ReadEnvironment(kRuntimeOptIn) == L"1";
}

#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)

bool IsRemoteOrUrlPath(const std::filesystem::path& path) {
  const std::wstring raw = path.native();
  if (raw.empty() || raw.rfind(L"\\\\", 0) == 0 ||
      raw.find(L"://") != std::wstring::npos) {
    return true;
  }

  std::error_code error;
  const auto absolute = std::filesystem::absolute(path, error);
  if (error || !absolute.has_root_name()) {
    return true;
  }

  std::wstring root = absolute.root_name().native();
  root.append(L"\\");
  const UINT drive_type = GetDriveTypeW(root.c_str());
  return drive_type == DRIVE_REMOTE || drive_type == DRIVE_UNKNOWN ||
         drive_type == DRIVE_NO_ROOT_DIR;
}

bool IsInsideDirectory(const std::filesystem::path& file,
                       const std::filesystem::path& directory) {
  std::error_code error;
  const auto relative = std::filesystem::relative(file, directory, error);
  if (error || relative.empty() || relative.is_absolute()) {
    return false;
  }
  const auto first = *relative.begin();
  return first != L"..";
}

std::string Utf8Path(const std::filesystem::path& path) {
  const std::u8string utf8 = path.u8string();
  return std::string(reinterpret_cast<const char*>(utf8.data()), utf8.size());
}

#endif

}  // namespace

class NeuraOnDeviceAsr::Impl {
 public:
  explicit Impl(NeuraOnDeviceAsr* owner) : owner_(owner) {}

  ~Impl() {
    Stop();
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    if (recognizer_ != nullptr) {
      SherpaOnnxDestroyOnlineRecognizer(recognizer_);
      recognizer_ = nullptr;
    }
    if (port_audio_initialized_) {
      Pa_Terminate();
      port_audio_initialized_ = false;
    }
#endif
  }

  bool IsAvailable() {
    if (!RuntimeOptedIn()) {
      return false;
    }
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    return EnsureInitialized();
#else
    return false;
#endif
  }

  bool Start(uint64_t generation) {
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    if (accepting_audio_.load() || !IsAvailable()) {
      return accepting_audio_.load();
    }

    stream_ = SherpaOnnxCreateOnlineStream(recognizer_);
    if (stream_ == nullptr) {
      return false;
    }

    PaStreamParameters input{};
    input.device = Pa_GetDefaultInputDevice();
    const PaDeviceInfo* device = Pa_GetDeviceInfo(input.device);
    if (input.device == paNoDevice || device == nullptr) {
      DestroyStream();
      return false;
    }
    input.channelCount = 1;
    input.sampleFormat = paFloat32;
    input.suggestedLatency = device->defaultLowInputLatency;

    generation_ = generation;
    transcript_.clear();
    last_partial_.clear();
    accepting_audio_.store(true);
    decode_running_.store(true);

    const PaError open_error = Pa_OpenStream(
        &audio_stream_, &input, nullptr, 16000.0,
        paFramesPerBufferUnspecified, paClipOff, &RecordCallback, this);
    if (open_error != paNoError) {
      accepting_audio_.store(false);
      decode_running_.store(false);
      DestroyStream();
      return false;
    }

    decoder_thread_ = std::thread(&Impl::DecodeLoop, this);
    const PaError start_error = Pa_StartStream(audio_stream_);
    if (start_error != paNoError) {
      accepting_audio_.store(false);
      Pa_CloseStream(audio_stream_);
      audio_stream_ = nullptr;
      decode_running_.store(false);
      if (decoder_thread_.joinable()) {
        decoder_thread_.join();
      }
      DestroyStream();
      return false;
    }
    return true;
#else
    static_cast<void>(generation);
    return false;
#endif
  }

  std::string Stop() {
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    accepting_audio_.store(false);
    if (audio_stream_ != nullptr) {
      if (Pa_IsStreamActive(audio_stream_) == 1) {
        Pa_StopStream(audio_stream_);
      }
      Pa_CloseStream(audio_stream_);
      audio_stream_ = nullptr;
    }

    decode_running_.store(false);
    if (decoder_thread_.joinable()) {
      decoder_thread_.join();
    }
    DestroyStream();

    std::string result = std::move(transcript_);
    transcript_.clear();
    last_partial_.clear();
    return result;
#else
    return {};
#endif
  }

 private:
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
  static int RecordCallback(const void* input_buffer, void*,
                            unsigned long frames_per_buffer,
                            const PaStreamCallbackTimeInfo*,
                            PaStreamCallbackFlags, void* user_data) {
    auto* self = static_cast<Impl*>(user_data);
    if (!self->accepting_audio_.load()) {
      return paComplete;
    }
    if (input_buffer != nullptr && self->stream_ != nullptr) {
      SherpaOnnxOnlineStreamAcceptWaveform(
          self->stream_, 16000, static_cast<const float*>(input_buffer),
          static_cast<int32_t>(frames_per_buffer));
    }
    return paContinue;
  }

  bool EnsureInitialized() {
    if (recognizer_ != nullptr) {
      return true;
    }

    const std::filesystem::path configured(ReadEnvironment(kModelDirectory));
    if (IsRemoteOrUrlPath(configured)) {
      return false;
    }

    std::error_code error;
    const auto model_directory = std::filesystem::canonical(configured, error);
    if (error ||
        !std::filesystem::is_directory(model_directory, error) || error ||
        IsRemoteOrUrlPath(model_directory)) {
      return false;
    }

    const auto encoder = model_directory / L"encoder.int4.onnx";
    const auto decoder = model_directory / L"decoder.int4.onnx";
    const auto joiner = model_directory / L"joiner.int4.onnx";
    const auto tokens = model_directory / L"tokens.txt";
    for (const auto& file : {encoder, decoder, joiner, tokens}) {
      const auto canonical = std::filesystem::canonical(file, error);
      if (error || !std::filesystem::is_regular_file(canonical, error) ||
          error || IsRemoteOrUrlPath(canonical) ||
          !IsInsideDirectory(canonical, model_directory)) {
        return false;
      }
    }

    encoder_path_ = Utf8Path(encoder);
    decoder_path_ = Utf8Path(decoder);
    joiner_path_ = Utf8Path(joiner);
    tokens_path_ = Utf8Path(tokens);

    if (!port_audio_initialized_) {
      if (Pa_Initialize() != paNoError) {
        return false;
      }
      port_audio_initialized_ = true;
    }

    const PaDeviceIndex input_device = Pa_GetDefaultInputDevice();
    const PaDeviceInfo* device = Pa_GetDeviceInfo(input_device);
    if (input_device == paNoDevice || device == nullptr) {
      return false;
    }
    PaStreamParameters input{};
    input.device = input_device;
    input.channelCount = 1;
    input.sampleFormat = paFloat32;
    input.suggestedLatency = device->defaultLowInputLatency;
    if (Pa_IsFormatSupported(&input, nullptr, 16000.0) != paFormatIsSupported) {
      return false;
    }

    SherpaOnnxOnlineRecognizerConfig config{};
    config.decoding_method = "greedy_search";
    config.max_active_paths = 4;
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.debug = 0;
    config.model_config.num_threads = 2;
    config.model_config.provider = "cpu";
    config.model_config.tokens = tokens_path_.c_str();
    config.model_config.transducer.encoder = encoder_path_.c_str();
    config.model_config.transducer.decoder = decoder_path_.c_str();
    config.model_config.transducer.joiner = joiner_path_.c_str();
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 1.2f;
    config.rule2_min_trailing_silence = 0.8f;
    config.rule3_min_utterance_length = 300.0f;

    recognizer_ = SherpaOnnxCreateOnlineRecognizer(&config);
    return recognizer_ != nullptr;
  }

  void DecodeLoop() {
    while (decode_running_.load()) {
      DecodeAvailable(false);
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    if (stream_ == nullptr) {
      return;
    }
    float tail_padding[4800]{};
    SherpaOnnxOnlineStreamAcceptWaveform(stream_, 16000, tail_padding, 4800);
    SherpaOnnxOnlineStreamInputFinished(stream_);
    DecodeAvailable(true);
  }

  void DecodeAvailable(bool finishing) {
    if (stream_ == nullptr || recognizer_ == nullptr) {
      return;
    }
    while (SherpaOnnxIsOnlineStreamReady(recognizer_, stream_)) {
      SherpaOnnxDecodeOnlineStream(recognizer_, stream_);
    }

    const SherpaOnnxOnlineRecognizerResult* result =
        SherpaOnnxGetOnlineStreamResult(recognizer_, stream_);
    if (result == nullptr) {
      return;
    }
    const std::string text = result->text == nullptr ? "" : result->text;
    SherpaOnnxDestroyOnlineRecognizerResult(result);

    const bool endpoint =
        SherpaOnnxOnlineStreamIsEndpoint(recognizer_, stream_) != 0;
    if ((endpoint || finishing) && !text.empty()) {
      AppendFinal(text);
    } else if (!text.empty() && text != last_partial_) {
      last_partial_ = text;
      owner_->QueueSegment(text, false, generation_);
    }

    if (endpoint) {
      SherpaOnnxOnlineStreamReset(recognizer_, stream_);
      last_partial_.clear();
    }
  }

  void AppendFinal(const std::string& text) {
    if (!transcript_.empty()) {
      transcript_.append(" ");
    }
    transcript_.append(text);
    last_partial_.clear();
    owner_->QueueSegment(text, true, generation_);
  }

  void DestroyStream() {
    if (stream_ != nullptr) {
      SherpaOnnxDestroyOnlineStream(stream_);
      stream_ = nullptr;
    }
  }

  const SherpaOnnxOnlineRecognizer* recognizer_ = nullptr;
  const SherpaOnnxOnlineStream* stream_ = nullptr;
  PaStream* audio_stream_ = nullptr;
  std::thread decoder_thread_;
  std::atomic<bool> accepting_audio_{false};
  std::atomic<bool> decode_running_{false};
  bool port_audio_initialized_ = false;
  uint64_t generation_ = 0;
  std::string encoder_path_;
  std::string decoder_path_;
  std::string joiner_path_;
  std::string tokens_path_;
  std::string transcript_;
  std::string last_partial_;
#endif

  NeuraOnDeviceAsr* owner_;
};

NeuraOnDeviceAsr::NeuraOnDeviceAsr(flutter::BinaryMessenger* messenger,
                                   HWND window)
    : window_(window),
      channel_(std::make_unique<
               flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "neura/on_device_asr",
          &flutter::StandardMethodCodec::GetInstance())),
      impl_(std::make_unique<Impl>(this)) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

NeuraOnDeviceAsr::~NeuraOnDeviceAsr() {
  channel_->SetMethodCallHandler(nullptr);
  listening_ = false;
  ++generation_;
  impl_->Stop();
  ClearPendingSegments();
  impl_.reset();
  channel_.reset();
}

void NeuraOnDeviceAsr::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "isAvailable") {
    result->Success(flutter::EncodableValue(impl_->IsAvailable()));
    return;
  }
  if (call.method_name() == "start") {
    if (listening_) {
      result->Success(flutter::EncodableValue(true));
      return;
    }
    ClearPendingSegments();
    const uint64_t next_generation = ++generation_;
    listening_ = impl_->Start(next_generation);
    result->Success(flutter::EncodableValue(listening_));
    return;
  }
  if (call.method_name() == "stop") {
    listening_ = false;
    ++generation_;
    std::string transcript = impl_->Stop();
    ClearPendingSegments();
    result->Success(flutter::EncodableValue(std::move(transcript)));
    return;
  }
  result->NotImplemented();
}

void NeuraOnDeviceAsr::QueueSegment(std::string text, bool is_final,
                                    uint64_t generation) {
  if (text.empty()) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    pending_segments_.push_back(
        PendingSegment{std::move(text), is_final, generation});
  }
  PostMessageW(window_, kDrainMessage, 0, 0);
}

void NeuraOnDeviceAsr::DrainPendingSegments() {
  std::deque<PendingSegment> pending;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    pending.swap(pending_segments_);
  }
  if (!listening_) {
    return;
  }

  for (auto& segment : pending) {
    if (segment.generation != generation_) {
      continue;
    }
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("text")] =
        flutter::EncodableValue(std::move(segment.text));
    payload[flutter::EncodableValue("is_final")] =
        flutter::EncodableValue(segment.is_final);
    channel_->InvokeMethod(
        "onSegment",
        std::make_unique<flutter::EncodableValue>(std::move(payload)));
  }
}

void NeuraOnDeviceAsr::ClearPendingSegments() {
  std::lock_guard<std::mutex> lock(pending_mutex_);
  pending_segments_.clear();
}
