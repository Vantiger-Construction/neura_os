import 'neura_speech_engine.dart';
import 'neura_speech_to_text_service.dart';
import 'voice_journal_service.dart';

final class NeuraWinRtSpeechEngineAdapter implements NeuraSpeechEngine {
  NeuraWinRtSpeechEngineAdapter({NeuraSpeechToTextService? service})
      : _service = service ?? NeuraSpeechToTextService.instance;

  final NeuraSpeechToTextService _service;

  @override
  String get id => 'windows_winrt';

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      const NeuraSpeechEngineCapabilities(
        // WinRT dictation can depend on the Windows online speech setting.
        // Keep it outside the verified-local registry until offline behavior
        // is demonstrated with network access disabled.
        onDevice: false,
        supportsPartialResults: true,
        supportsConfidence: true,
        supportedPlatforms: {'windows'},
      );

  @override
  Stream<NeuraSpeechSegment> get segments => _service.segmentStream;

  @override
  bool get isListening => _service.isListening;

  @override
  Future<bool> isAvailable() => _service.isAvailable();

  @override
  Future<bool> start() => _service.startRecording();

  @override
  Future<String> stop() => _service.stopRecording();
}

final class NeuraPlatformSpeechEngineAdapter implements NeuraSpeechEngine {
  NeuraPlatformSpeechEngineAdapter(this._service);

  final VoiceJournalService _service;

  @override
  String get id => 'platform_speech_to_text';

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      const NeuraSpeechEngineCapabilities(
        // Android and Apple platform recognizers may use remote services
        // unless their native on-device-only APIs are explicitly requested.
        onDevice: false,
        supportsPartialResults: true,
        supportsConfidence: true,
        supportedPlatforms: {'android', 'ios', 'macos', 'web'},
      );

  @override
  Stream<NeuraSpeechSegment> get segments => _service.segmentStream;

  @override
  bool get isListening => _service.isListening;

  @override
  Future<bool> isAvailable() async => _service.listeningAllowed;

  @override
  Future<bool> start() => _service.startRecording();

  @override
  Future<String> stop() => _service.stopRecording();
}
