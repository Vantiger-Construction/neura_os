#include "neura_windows_tts.h"

#include <cmath>
#include <cwchar>
#include <stdexcept>
#include <utility>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

void Check(HRESULT result) {
  if (FAILED(result)) throw std::runtime_error("Local speech operation failed");
}

std::wstring Wide(const std::string& text) {
  if (text.empty() || text.size() > 65536 || text.find('\0') != std::string::npos) {
    throw std::invalid_argument("Invalid local speech text");
  }
  const int size = static_cast<int>(text.size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       text.data(), size, nullptr, 0);
  if (count <= 0) throw std::invalid_argument("Invalid local speech text");
  std::wstring result(static_cast<size_t>(count), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), size,
                          result.data(), count) != count) {
    throw std::invalid_argument("Invalid local speech text");
  }
  return result;
}

std::string Utf8(const std::wstring& text) {
  if (text.empty() || text.size() > 4096) return {};
  const int size = static_cast<int>(text.size());
  const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                       text.data(), size, nullptr, 0, nullptr, nullptr);
  if (count <= 0) return {};
  std::string result(static_cast<size_t>(count), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), size,
                          result.data(), count, nullptr, nullptr) != count) return {};
  return result;
}

std::wstring Attribute(ISpDataKey* key, const wchar_t* name) {
  wchar_t* raw = nullptr;
  if (FAILED(key->GetStringValue(name, &raw)) || !raw) return {};
  std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> owned(raw, CoTaskMemFree);
  // Installed voice metadata is bounded before exposing it to Dart.
  size_t count = 0;
  while (count <= 4096 && raw[count] != L'\0') ++count;
  return count <= 4096 ? std::wstring(raw, count) : std::wstring();
}

const Value& Field(const Map& map, const char* key) {
  const auto it = map.find(Value(key));
  if (it == map.end()) throw std::invalid_argument("Missing local speech field");
  return it->second;
}

int64_t Id(const Value& value) {
  if (const auto* id = std::get_if<int64_t>(&value)) return *id;
  if (const auto* id = std::get_if<int32_t>(&value)) return *id;
  throw std::invalid_argument("Invalid local speech identity");
}

double Number(const Value* value, double low, double high) {
  const auto* number = value ? std::get_if<double>(value) : nullptr;
  if (!number || !std::isfinite(*number) || *number < low || *number > high) {
    throw std::invalid_argument("Invalid local speech setting");
  }
  return *number;
}
}  // namespace

NeuraWindowsTts::NeuraWindowsTts(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "neura/speech_synthesis", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}

NeuraWindowsTts::~NeuraWindowsTts() {
  channel_->SetMethodCallHandler(nullptr);
  Background();
  voices_.clear();
  voice_.reset();
}

void NeuraWindowsTts::EnsureVoice() {
  EnsureCatalog();
  if (voices_.empty()) throw std::runtime_error("No local desktop voice installed");
  if (voice_) return;
  ISpVoice* raw = nullptr;
  Check(CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_INPROC_SERVER,
                         IID_ISpVoice, reinterpret_cast<void**>(&raw)));
  voice_.reset(raw);
  const ULONGLONG events = SPFEI(SPEI_START_INPUT_STREAM) | SPFEI(SPEI_END_INPUT_STREAM);
  Check(voice_->SetInterest(events, events));
  // Never send text to an arbitrary system-default/third-party SAPI engine.
  Check(voice_->SetVoice(voices_[selected_voice_].token.get()));
  Check(voice_->SetRate(rate_));
  Check(voice_->SetVolume(volume_));
}

void NeuraWindowsTts::EnsureCatalog() {
  if (lifecycle_.state() == "failed") throw std::runtime_error("Local speech unavailable");
  if (!catalog_loaded_) {
    LoadVoices();
    catalog_loaded_ = true;
  }
}

void NeuraWindowsTts::LoadVoices() {
  ISpObjectTokenCategory* raw_category = nullptr;
  Check(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr, CLSCTX_INPROC_SERVER,
                         IID_ISpObjectTokenCategory, reinterpret_cast<void**>(&raw_category)));
  NeuraComPtr<ISpObjectTokenCategory> category(raw_category);
  Check(category->SetId(SPCAT_VOICES, FALSE));
  IEnumSpObjectTokens* raw_tokens = nullptr;
  Check(category->EnumTokens(L"Vendor=Microsoft", nullptr, &raw_tokens));
  NeuraComPtr<IEnumSpObjectTokens> tokens(raw_tokens);
  for (size_t i = 0; i < 128; ++i) {
    ISpObjectToken* raw_token = nullptr;
    ULONG fetched = 0;
    Check(tokens->Next(1, &raw_token, &fetched));
    if (!fetched || !raw_token) break;
    Voice voice;
    voice.token.reset(raw_token);
    wchar_t* raw_id = nullptr;
    Check(raw_token->GetId(&raw_id));
    if (!raw_id) continue;
    std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> owned_id(raw_id, CoTaskMemFree);
    const std::wstring token_id(raw_id);
    const auto separator = token_id.find_last_of(L'\\');
    const auto leaf = token_id.substr(separator == std::wstring::npos ? 0 : separator + 1);
    // Installed Microsoft desktop voice tokens only. No custom/online SAPI
    // providers, registry edits, downloaded models or cloud fallback.
    if (leaf.rfind(L"TTS_MS_", 0) != 0) continue;
    voice.name = Utf8(Attribute(raw_token, nullptr));
    ISpDataKey* raw_attributes = nullptr;
    if (SUCCEEDED(raw_token->OpenKey(L"Attributes", &raw_attributes)) && raw_attributes) {
      NeuraComPtr<ISpDataKey> attributes(raw_attributes);
      voice.gender = Utf8(Attribute(attributes.get(), L"Gender"));
      const auto language = Attribute(attributes.get(), L"Language");
      wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
      wchar_t* end = nullptr;
      const unsigned long lcid = std::wcstoul(language.c_str(), &end, 16);
      if (end != language.c_str() && lcid <= 0xffff &&
          LCIDToLocaleName(static_cast<LCID>(lcid), locale, LOCALE_NAME_MAX_LENGTH, 0)) {
        voice.locale = Utf8(locale);
      }
    }
    if (!voice.name.empty() && !voice.locale.empty()) voices_.push_back(std::move(voice));
  }
}

void NeuraWindowsTts::Drain() {
  if (!voice_) return;
  for (int i = 0; i < 128; ++i) {
    SPEVENT event = {};
    ULONG fetched = 0;
    Check(voice_->GetEvents(1, &event, &fetched));
    if (!fetched) break;
    // Only start/end stream events were requested; neither carries a resource.
    if (event.eEventId == SPEI_END_INPUT_STREAM) lifecycle_.End(voice_request_, event.ulStreamNum);
  }
  if (lifecycle_.state() == "completed") {
    SPVOICESTATUS status = {};
    Check(voice_->GetStatus(&status, nullptr));
    Check(status.hrLastResult);
  }
}

void NeuraWindowsTts::Stop() {
  lifecycle_.Cancel();  // Revoke identity before purging queued/current audio.
  auto voice = std::move(voice_);
  voice_request_ = 0;
  if (voice) Check(voice->Speak(nullptr, SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML, nullptr));
  voice.reset();
  utterance_.clear();
}

void NeuraWindowsTts::Background() noexcept {
  try {
    Stop();
  } catch (...) {
    lifecycle_.Fail();
  }
}

void NeuraWindowsTts::Handle(
    const flutter::MethodCall<Value>& call,
    std::unique_ptr<flutter::MethodResult<Value>> result) {
  try {
    const auto& method = call.method_name();
    if (method == "stop") {
      Stop();
      result->Success(Value(1));
      return;
    }
    if (method != "getVoices" && method != "setVoice" && method != "setSpeechRate" &&
        method != "setPitch" && method != "setVolume" && method != "speak" && method != "poll") {
      result->NotImplemented();
      return;
    }
    EnsureCatalog();
    if (method == "getVoices") {
      flutter::EncodableList voices;
      for (const auto& voice : voices_) {
        voices.emplace_back(Map{{Value("name"), Value(voice.name)},
                                {Value("locale"), Value(voice.locale)},
                                {Value("gender"), Value(voice.gender)}});
      }
      result->Success(Value(voices));
    } else if (method == "setVoice") {
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args || args->size() != 2) throw std::invalid_argument("Invalid voice selection");
      const auto& name = std::get<std::string>(Field(*args, "name"));
      const auto& locale = std::get<std::string>(Field(*args, "locale"));
      int accepted = 0;
      for (size_t i = 0; i < voices_.size(); ++i) {
        const auto& voice = voices_[i];
        if (voice.name == name && voice.locale == locale) {
          if (voice_) Check(voice_->SetVoice(voice.token.get()));
          selected_voice_ = i;
          accepted = 1;
          break;
        }
      }
      result->Success(Value(accepted));
    } else if (method == "setSpeechRate") {
      const auto rate = Number(call.arguments(), 0.25, 0.75);
      rate_ = static_cast<LONG>(std::lround((rate - 0.5) * 20));
      if (voice_) Check(voice_->SetRate(rate_));
      result->Success(Value(1));
    } else if (method == "setPitch") {
      const auto pitch = Number(call.arguments(), 0.5, 2.0);
      pitch_ = static_cast<int>(std::lround(10 * std::log2(pitch)));
      result->Success(Value(1));
    } else if (method == "setVolume") {
      const auto volume = Number(call.arguments(), 0, 1);
      volume_ = static_cast<USHORT>(std::lround(volume * 100));
      if (voice_) Check(voice_->SetVolume(volume_));
      result->Success(Value(1));
    } else if (method == "speak") {
      if (voices_.empty()) throw std::runtime_error("No local desktop voice installed");
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args || args->size() != 2) throw std::invalid_argument("Invalid speech request");
      const int64_t id = Id(Field(*args, "id"));
      if (!lifecycle_.CanStart(id)) throw std::invalid_argument("Invalid speech lifecycle");
      const auto text = Wide(std::get<std::string>(Field(*args, "text")));
      // SAPI stream numbers reset to 1 after an empty queue. Give every
      // utterance a fresh COM voice/event queue so old events cannot be
      // reinterpreted as events for that reused stream number.
      Stop();
      EnsureVoice();
      utterance_ = NeuraTtsPitchText(text, pitch_);
      ULONG stream = 0;
      Check(voice_->Speak(utterance_.c_str(), SPF_ASYNC | SPF_IS_XML | SPF_PARSE_SAPI, &stream));
      if (!lifecycle_.Start(id, stream)) {
        Stop();
        throw std::runtime_error("Local speech identity unavailable");
      }
      voice_request_ = id;
      result->Success(Value(1));
    } else if (method == "poll") {
      Drain();
      result->Success(Value(Map{{Value("id"), Value(lifecycle_.request())},
                                {Value("state"), Value(lifecycle_.state())}}));
    }
  } catch (const std::invalid_argument&) {
    result->Error("invalid_speech_request", "Local speech rejected the request.");
  } catch (...) {
    Background();
    lifecycle_.Fail();
    result->Error("local_speech_unavailable", "Local speech requires an application restart.");
  }
}
