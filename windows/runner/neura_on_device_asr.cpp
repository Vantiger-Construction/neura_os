#include "neura_on_device_asr.h"

#include <filesystem>
#include <string>
#include <system_error>
#include <utility>

#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
#include "neura_asr_session.h"
#include <portaudio.h>
#include <sherpa-onnx/c-api/c-api.h>
#endif

namespace {

constexpr wchar_t kRuntimeOptIn[] = L"NEURA_ON_DEVICE_ASR_ENABLE";
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
constexpr wchar_t kModelDirectory[] = L"NEURA_ON_DEVICE_ASR_MODEL_DIR";
constexpr wchar_t kModelProfile[] = L"NEURA_ON_DEVICE_ASR_MODEL_PROFILE";
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

// Reject junctions/symlinks and cloud placeholders before canonicalization or
// model reads can follow them onto a remote volume or hydrate a cloud file.
bool IsPlainLocalPath(const std::filesystem::path& path) {
  if (!path.is_absolute() || IsRemoteOrUrlPath(path)) return false;
  auto current = path.root_path();
  for (const auto& component : path.relative_path()) {
    if (component == L"..") return false;
    current /= component;
    const auto attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_OFFLINE))) {
      return false;
    }
  }
  return true;
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

class NeuraOnDeviceAsr::Impl
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    : public neura::AsrBackend
#endif
{
 public:
  explicit Impl(NeuraOnDeviceAsr* owner)
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
      : session_(*this, &DeliverSegment, owner)
#endif
  {
    static_cast<void>(owner);
  }

  ~Impl() {
    Stop(true);
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    if (recognizer_ != nullptr) SherpaOnnxDestroyOnlineRecognizer(recognizer_);
    if (port_audio_initialized_) Pa_Terminate();
#endif
  }

  bool IsAvailable() {
    if (!RuntimeOptedIn()) return false;
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    // Device availability can change even after a model was initialized.
    return EnsureInitialized() && HasCompatibleInput();
#else
    return false;
#endif
  }

  bool Start(uint64_t generation) {
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    return IsAvailable() && session_.Start(generation);
#else
    static_cast<void>(generation);
    return false;
#endif
  }

  std::string Stop(bool discard = true) {
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
    return session_.Stop(discard);
#else
    static_cast<void>(discard);
    return {};
#endif
  }

 private:
#if defined(NEURA_WINDOWS_ON_DEVICE_ASR)
  static void DeliverSegment(std::string text, bool is_final,
                             uint64_t generation, void* context) {
    static_cast<NeuraOnDeviceAsr*>(context)->QueueSegment(
        std::move(text), is_final, generation);
  }

  static int RecordCallback(const void* input_buffer, void*,
                            unsigned long frames_per_buffer,
                            const PaStreamCallbackTimeInfo*,
                            PaStreamCallbackFlags, void* user_data) {
    auto* self = static_cast<Impl*>(user_data);
    return self->capture_(static_cast<const float*>(input_buffer),
                          frames_per_buffer, self->capture_context_)
               ? paContinue
               : paComplete;
  }

  bool HasCompatibleInput() const {
    const PaDeviceIndex input_device = Pa_GetDefaultInputDevice();
    const PaDeviceInfo* device = Pa_GetDeviceInfo(input_device);
    if (input_device == paNoDevice || device == nullptr) return false;
    PaStreamParameters input{};
    input.device = input_device;
    input.channelCount = 1;
    input.sampleFormat = paFloat32;
    input.suggestedLatency = device->defaultLowInputLatency;
    return Pa_IsFormatSupported(&input, nullptr, 16000.0) == paFormatIsSupported;
  }

  bool EnsureInitialized() {
    if (recognizer_ != nullptr) {
      return true;
    }

    const std::filesystem::path configured(ReadEnvironment(kModelDirectory));
    if (!IsPlainLocalPath(configured)) {
      return false;
    }

    std::error_code error;
    const auto model_directory = std::filesystem::canonical(configured, error);
    if (error ||
        !std::filesystem::is_directory(model_directory, error) || error ||
        IsRemoteOrUrlPath(model_directory)) {
      return false;
    }

    const auto profile = ReadEnvironment(kModelProfile);
    auto encoder = model_directory / L"encoder.int4.onnx";
    auto decoder = model_directory / L"decoder.int4.onnx";
    auto joiner = model_directory / L"joiner.int4.onnx";
    if (profile == L"zipformer-en-2023-06-26-int8") {
      encoder = model_directory /
          L"encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx";
      decoder = model_directory /
          L"decoder-epoch-99-avg-1-chunk-16-left-128.onnx";
      joiner = model_directory /
          L"joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx";
    } else if (!profile.empty() && profile != L"int4") {
      return false;
    }
    const auto tokens = model_directory / L"tokens.txt";
    for (const auto& file : {encoder, decoder, joiner, tokens}) {
      if (!IsPlainLocalPath(file)) return false;
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

    if (!HasCompatibleInput()) return false;

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


  bool CreateStream() override {
    stream_ = SherpaOnnxCreateOnlineStream(recognizer_);
    return stream_ != nullptr;
  }

  bool OpenInput(Capture capture, void* context) override {
    capture_ = capture;
    capture_context_ = context;
    PaStreamParameters input{};
    input.device = Pa_GetDefaultInputDevice();
    const PaDeviceInfo* device = Pa_GetDeviceInfo(input.device);
    if (input.device == paNoDevice || device == nullptr) return false;
    input.channelCount = 1;
    input.sampleFormat = paFloat32;
    input.suggestedLatency = device->defaultLowInputLatency;
    return Pa_OpenStream(&audio_stream_, &input, nullptr, 16000.0,
                         paFramesPerBufferUnspecified, paClipOff,
                         &RecordCallback, this) == paNoError;
  }

  bool StartInput() override {
    return Pa_StartStream(audio_stream_) == paNoError;
  }

  void CloseInput() noexcept override {
    if (audio_stream_ != nullptr) {
      if (Pa_IsStreamActive(audio_stream_) == 1) Pa_StopStream(audio_stream_);
      Pa_CloseStream(audio_stream_);
      audio_stream_ = nullptr;
    }
  }

  void DestroyStream() noexcept override {
    if (stream_ != nullptr) {
      SherpaOnnxDestroyOnlineStream(stream_);
      stream_ = nullptr;
    }
  }

  void Accept(const float* samples, size_t count) override {
    SherpaOnnxOnlineStreamAcceptWaveform(
        stream_, 16000, samples, static_cast<int32_t>(count));
  }

  bool IsReady() override {
    return SherpaOnnxIsOnlineStreamReady(recognizer_, stream_) != 0;
  }

  void Decode() override {
    SherpaOnnxDecodeOnlineStream(recognizer_, stream_);
  }

  neura::AsrResult Result() override {
    const auto* result = SherpaOnnxGetOnlineStreamResult(recognizer_, stream_);
    if (result == nullptr) return {};
    // Always release native text, including when string allocation throws.
    const auto destroy = &SherpaOnnxDestroyOnlineRecognizerResult;
    const std::unique_ptr<const SherpaOnnxOnlineRecognizerResult,
                          decltype(destroy)> owned(result, destroy);
    return {result->text == nullptr ? "" : result->text,
            SherpaOnnxOnlineStreamIsEndpoint(recognizer_, stream_) != 0};
  }

  void Reset() override {
    SherpaOnnxOnlineStreamReset(recognizer_, stream_);
  }

  void FinishInput() override {
    const float tail_padding[4800]{};
    SherpaOnnxOnlineStreamAcceptWaveform(stream_, 16000, tail_padding, 4800);
    SherpaOnnxOnlineStreamInputFinished(stream_);
  }

  const SherpaOnnxOnlineRecognizer* recognizer_ = nullptr;
  const SherpaOnnxOnlineStream* stream_ = nullptr;
  PaStream* audio_stream_ = nullptr;
  Capture capture_ = nullptr;
  void* capture_context_ = nullptr;
  bool port_audio_initialized_ = false;
  std::string encoder_path_;
  std::string decoder_path_;
  std::string joiner_path_;
  std::string tokens_path_;
  neura::AsrSession session_;
#endif
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
    // Safe Mode/disposal can request a discard without flushing pending audio.
    bool discard = false;
    const auto* arguments = call.arguments();
    const auto* map = arguments == nullptr
                          ? nullptr
                          : std::get_if<flutter::EncodableMap>(arguments);
    if (map != nullptr) {
      const auto flag = map->find(flutter::EncodableValue("discard"));
      if (flag != map->end()) {
        const auto* value = std::get_if<bool>(&flag->second);
        discard = value != nullptr && *value;
      }
    }
    std::string transcript = impl_->Stop(discard);
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
    // Bound text awaiting the UI even when the window thread is busy.
    if (pending_segments_.size() >= 32) pending_segments_.pop_front();
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
