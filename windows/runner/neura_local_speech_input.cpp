#include "neura_local_speech_input.h"

#include <stdexcept>
#include <string>
#include <utility>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
void Check(HRESULT hr) {
  if (FAILED(hr)) throw std::runtime_error("Local speech input unavailable");
}
int64_t Session(const Value* args) {
  const auto* map = args ? std::get_if<Map>(args) : nullptr;
  if (!map) throw std::invalid_argument("Missing speech session");
  const auto field = map->find(Value("session"));
  if (field == map->end()) throw std::invalid_argument("Missing speech session");
  if (const auto* id = std::get_if<int64_t>(&field->second)) return *id;
  if (const auto* id = std::get_if<int32_t>(&field->second)) return *id;
  throw std::invalid_argument("Invalid speech session");
}
std::string Text(ISpRecoResult* result) {
  wchar_t* raw = nullptr;
  Check(result->GetText(SP_GETWHOLEPHRASE, SP_GETWHOLEPHRASE, TRUE, &raw, nullptr));
  std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> owned(raw, CoTaskMemFree);
  if (!raw) return {};
  size_t size = 0;
  while (size <= 8192 && raw[size]) ++size;
  if (!size || size > 8192) return {};
  const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, raw,
      static_cast<int>(size), nullptr, 0, nullptr, nullptr);
  if (count <= 0 || count > 16384) return {};
  std::string text(static_cast<size_t>(count), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, raw,
      static_cast<int>(size), text.data(), count, nullptr, nullptr) != count) return {};
  return text;
}
}  // namespace

NeuraLocalSpeechInput::NeuraLocalSpeechInput(
    flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "neura/local_speech_input", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}

NeuraLocalSpeechInput::~NeuraLocalSpeechInput() {
  channel_->SetMethodCallHandler(nullptr);
  Background();
}

NeuraLocalSpeechInput::ComPtr<ISpObjectToken> NeuraLocalSpeechInput::FindEngine() {
  ISpObjectTokenCategory* raw_category = nullptr;
  Check(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr, CLSCTX_INPROC_SERVER,
      IID_ISpObjectTokenCategory, reinterpret_cast<void**>(&raw_category)));
  ComPtr<ISpObjectTokenCategory> category(raw_category);
  Check(category->SetId(SPCAT_RECOGNIZERS, FALSE));
  IEnumSpObjectTokens* raw_tokens = nullptr;
  Check(category->EnumTokens(L"Vendor=Microsoft", nullptr, &raw_tokens));
  ComPtr<IEnumSpObjectTokens> tokens(raw_tokens);
  for (int i = 0; i < 128; ++i) {
    ISpObjectToken* raw_token = nullptr;
    ULONG fetched = 0;
    Check(tokens->Next(1, &raw_token, &fetched));
    ComPtr<ISpObjectToken> token(raw_token);
    if (!fetched || !token) break;
    wchar_t* raw_id = nullptr;
    Check(token->GetId(&raw_id));
    std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> id(raw_id, CoTaskMemFree);
    if (!raw_id) continue;
    const std::wstring path(raw_id);
    const auto separator = path.find_last_of(L'\\');
    const auto leaf = path.substr(separator == std::wstring::npos ? 0 : separator + 1);
    // Installed Microsoft desktop engine tokens only; never a system-default
    // or third-party/online recognizer. Missing language packs fail closed.
    if (leaf.rfind(L"MS-", 0) == 0 && leaf.find(L"-DESK") != std::wstring::npos) {
      return token;
    }
  }
  return {};
}

void NeuraLocalSpeechInput::Start(int64_t session) {
  Background();
  if (session <= 0 || GetForegroundWindow() != window_ || IsIconic(window_)) {
    throw std::runtime_error("Speech input requires the foreground window");
  }
  auto token = FindEngine();
  if (!token) throw std::runtime_error("No local Microsoft speech engine");
  ISpRecognizer* raw_recognizer = nullptr;
  Check(CoCreateInstance(CLSID_SpInprocRecognizer, nullptr, CLSCTX_INPROC_SERVER,
      IID_ISpRecognizer, reinterpret_cast<void**>(&raw_recognizer)));
  recognizer_.reset(raw_recognizer);
  Check(recognizer_->SetRecognizer(token.get()));
  Check(recognizer_->SetRecoState(SPRST_INACTIVE_WITH_PURGE));
  ISpAudio* raw_audio = nullptr;
  Check(CoCreateInstance(CLSID_SpMMAudioIn, nullptr, CLSCTX_INPROC_SERVER,
      IID_ISpAudio, reinterpret_cast<void**>(&raw_audio)));
  audio_.reset(raw_audio);
  Check(recognizer_->SetInput(audio_.get(), TRUE));
  ISpRecoContext* raw_context = nullptr;
  Check(recognizer_->CreateRecoContext(&raw_context));
  context_.reset(raw_context);
  const ULONGLONG events = SPFEI(SPEI_RECOGNITION) | SPFEI(SPEI_END_SR_STREAM);
  Check(context_->SetInterest(events, events));
  ISpRecoGrammar* raw_grammar = nullptr;
  Check(context_->CreateGrammar(1, &raw_grammar));
  grammar_.reset(raw_grammar);
  Check(grammar_->LoadDictation(nullptr, SPLO_STATIC));
  Check(grammar_->SetDictationState(SPRS_ACTIVE));
  Check(recognizer_->SetRecoState(SPRST_ACTIVE));
  session_ = session;
}

Map NeuraLocalSpeechInput::Poll() {
  const auto session = session_;
  Map packet{{Value("session"), Value(session)},
             {Value("listening"), Value(recognizer_ != nullptr)}};
  if (!context_) return packet;
  for (int i = 0; i < 64; ++i) {
    SPEVENT event = {};
    ULONG fetched = 0;
    Check(context_->GetEvents(1, &event, &fetched));
    if (!fetched) break;
    // SAPI transfers ownership of event resources to the consumer.
    ComPtr<IUnknown> resource(event.elParamType == SPET_LPARAM_IS_OBJECT
        ? reinterpret_cast<IUnknown*>(event.lParam) : nullptr);
    if (event.eEventId == SPEI_RECOGNITION && resource) {
      const auto text = Text(reinterpret_cast<ISpRecoResult*>(event.lParam));
      if (!text.empty()) {
        packet[Value("text")] = Value(text);
        packet[Value("final")] = Value(true);
        break;  // One bounded utterance; Dart stops before generating a reply.
      }
    } else if (event.eEventId == SPEI_END_SR_STREAM) {
      Background();
      packet[Value("listening")] = Value(false);
      break;
    }
  }
  return packet;
}

void NeuraLocalSpeechInput::Background() noexcept {
  session_ = 0;
  if (recognizer_) recognizer_->SetRecoState(SPRST_INACTIVE_WITH_PURGE);
  grammar_.reset();
  context_.reset();
  recognizer_.reset();
  audio_.reset();
}

void NeuraLocalSpeechInput::Handle(const flutter::MethodCall<Value>& call,
    std::unique_ptr<flutter::MethodResult<Value>> result) {
  try {
    if (call.method_name() == "isAvailable") {
      result->Success(Value(FindEngine() != nullptr));
    } else if (call.method_name() == "start") {
      Start(Session(call.arguments()));
      result->Success(Value(true));
    } else if (call.method_name() == "stop") {
      const auto session = Session(call.arguments());
      if (session >= session_) Background();
      result->Success();
    } else if (call.method_name() == "poll") {
      const auto session = Session(call.arguments());
      if (GetForegroundWindow() != window_ || IsIconic(window_)) Background();
      if (session != session_) {
        result->Success(Value(Map{{Value("session"), Value(session)},
                                  {Value("listening"), Value(false)}}));
      } else {
        result->Success(Value(Poll()));
      }
    } else {
      result->NotImplemented();
    }
  } catch (...) {
    Background();
    result->Error("local_speech_unavailable", "Local speech input is unavailable.");
  }
}
