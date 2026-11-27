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
// Fixed, content-free failure codes reported to Dart for diagnostics.
struct SpeechFailure : std::runtime_error {
  explicit SpeechFailure(const char* code) : std::runtime_error(code) {}
};
void Check(HRESULT hr, const char* code) {
  if (FAILED(hr)) throw SpeechFailure(code);
}
bool IsNeuraForeground(HWND window) {
  const HWND foreground = GetForegroundWindow();
  if (!foreground || !window || IsIconic(window)) return false;
  // Compare top-level roots so a focused child or owned popup of Neura's own
  // window still counts, while any other application does not.
  return GetAncestor(foreground, GA_ROOT) == GetAncestor(window, GA_ROOT);
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
// Optional "language" argument: one of Neura's listening languages, or
// absent/"auto" for the first installed engine. Anything else is refused.
std::string Language(const Value* args) {
  const auto* map = args ? std::get_if<Map>(args) : nullptr;
  if (!map) return {};
  const auto field = map->find(Value("language"));
  if (field == map->end()) return {};
  const auto* value = std::get_if<std::string>(&field->second);
  if (!value || *value == "auto") return {};
  if (*value == "en" || *value == "es" || *value == "it" || *value == "de" ||
      *value == "fr") {
    return *value;
  }
  throw SpeechFailure("unsupported_language");
}
// Microsoft desktop engine tokens are named "MS-<decimal LCID>-80-DESK".
// Returns the two-letter code of the LCID's primary language, if Neura
// listens in it.
std::string EngineLanguage(const std::wstring& leaf) {
  const auto start = leaf.find(L'-');
  const auto end = start == std::wstring::npos ? start : leaf.find(L'-', start + 1);
  if (end == std::wstring::npos || end - start < 2 || end - start > 6) return {};
  unsigned long lcid = 0;
  for (auto i = start + 1; i < end; ++i) {
    if (leaf[i] < L'0' || leaf[i] > L'9') return {};
    lcid = lcid * 10 + static_cast<unsigned long>(leaf[i] - L'0');
  }
  switch (lcid & 0x3ff) {
    case 0x09: return "en";
    case 0x0a: return "es";
    case 0x10: return "it";
    case 0x07: return "de";
    case 0x0c: return "fr";
    default: return {};
  }
}
std::string Text(ISpRecoResult* result) {
  wchar_t* raw = nullptr;
  // SAPI declares this all-elements sentinel as a signed enum, while GetText
  // accepts ULONG. Preserve its bit pattern explicitly under MSVC /W4 /WX.
  constexpr ULONG whole_phrase = static_cast<ULONG>(SP_GETWHOLEPHRASE);
  Check(result->GetText(whole_phrase, whole_phrase, TRUE, &raw, nullptr));
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
// Desktop dictation turns room noise and mumbles into plausible words. A
// phrase SAPI itself rates low, or whose words are mostly rated low, goes to
// the person for review instead of being sent as if they had said it.
bool Unsure(ISpRecoResult* result) {
  SPPHRASE* raw = nullptr;
  if (FAILED(result->GetPhrase(&raw)) || !raw) return true;
  std::unique_ptr<SPPHRASE, decltype(&CoTaskMemFree)> phrase(raw, CoTaskMemFree);
  if (phrase->Rule.Confidence == SP_LOW_CONFIDENCE) return true;
  const ULONG count = phrase->Rule.ulCountOfElements;
  if (!count || !phrase->pElements) return false;
  ULONG low = 0;
  for (ULONG i = 0; i < count; ++i) {
    if (phrase->pElements[i].ActualConfidence == SP_LOW_CONFIDENCE) ++low;
  }
  return low * 2 > count;
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

NeuraLocalSpeechInput::ComPtr<ISpObjectToken> NeuraLocalSpeechInput::FindEngine(
    const std::string& language, std::string* found) {
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
      const auto engine_language = EngineLanguage(leaf);
      // A requested language never falls back to an engine for another one.
      if (!language.empty() && engine_language != language) continue;
      if (found) *found = engine_language;
      return token;
    }
  }
  return {};
}

void NeuraLocalSpeechInput::Start(int64_t session, const std::string& language) {
  Background();
  if (session <= 0 || !IsNeuraForeground(window_)) {
    throw SpeechFailure("not_foreground");
  }
  ComPtr<ISpObjectToken> token;
  std::string engine_language;
  try {
    token = FindEngine(language, &engine_language);
  } catch (...) {
    throw SpeechFailure("no_local_engine");
  }
  if (!token) {
    throw SpeechFailure(language.empty() ? "no_local_engine"
                                         : "no_language_engine");
  }
  ISpRecognizer* raw_recognizer = nullptr;
  Check(CoCreateInstance(CLSID_SpInprocRecognizer, nullptr, CLSCTX_INPROC_SERVER,
      IID_ISpRecognizer, reinterpret_cast<void**>(&raw_recognizer)), "recognizer");
  recognizer_.reset(raw_recognizer);
  Check(recognizer_->SetRecognizer(token.get()), "recognizer");
  Check(recognizer_->SetRecoState(SPRST_INACTIVE_WITH_PURGE), "recognizer");
  ISpAudio* raw_audio = nullptr;
  Check(CoCreateInstance(CLSID_SpMMAudioIn, nullptr, CLSCTX_INPROC_SERVER,
      IID_ISpAudio, reinterpret_cast<void**>(&raw_audio)), "microphone");
  audio_.reset(raw_audio);
  Check(recognizer_->SetInput(audio_.get(), TRUE), "microphone");
  ISpRecoContext* raw_context = nullptr;
  Check(recognizer_->CreateRecoContext(&raw_context), "recognizer");
  context_.reset(raw_context);
  const ULONGLONG events = SPFEI(SPEI_RECOGNITION) | SPFEI(SPEI_END_SR_STREAM);
  Check(context_->SetInterest(events, events), "recognizer");
  ISpRecoGrammar* raw_grammar = nullptr;
  Check(context_->CreateGrammar(1, &raw_grammar), "dictation");
  grammar_.reset(raw_grammar);
  Check(grammar_->LoadDictation(nullptr, SPLO_STATIC), "dictation");
  Check(grammar_->SetDictationState(SPRS_ACTIVE), "dictation");
  // Opening the capture device happens on activation.
  Check(recognizer_->SetRecoState(SPRST_ACTIVE), "microphone");
  session_ = session;
  language_ = engine_language;
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
      auto* result = reinterpret_cast<ISpRecoResult*>(event.lParam);
      const auto text = Text(result);
      if (!text.empty()) {
        packet[Value("text")] = Value(text);
        packet[Value("final")] = Value(true);
        if (!language_.empty()) packet[Value("language")] = Value(language_);
        if (Unsure(result)) packet[Value("unsure")] = Value(true);
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
  language_.clear();
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
      result->Success(Value(FindEngine(Language(call.arguments())) != nullptr));
    } else if (call.method_name() == "start") {
      Start(Session(call.arguments()), Language(call.arguments()));
      result->Success(Value(true));
    } else if (call.method_name() == "stop") {
      const auto session = Session(call.arguments());
      if (session >= session_) Background();
      result->Success();
    } else if (call.method_name() == "poll") {
      const auto session = Session(call.arguments());
      if (!IsNeuraForeground(window_)) Background();
      if (session != session_) {
        result->Success(Value(Map{{Value("session"), Value(session)},
                                  {Value("listening"), Value(false)}}));
      } else {
        result->Success(Value(Poll()));
      }
    } else {
      result->NotImplemented();
    }
  } catch (const SpeechFailure& failure) {
    Background();
    result->Error("local_speech_unavailable", "Local speech input is unavailable.",
                  Value(std::string(failure.what())));
  } catch (...) {
    Background();
    result->Error("local_speech_unavailable", "Local speech input is unavailable.");
  }
}
