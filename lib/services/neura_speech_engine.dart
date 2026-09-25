import 'dart:async';

/// Provider-neutral speech seam used by chat, journaling, and device
/// benchmarks. Locality is declared in [NeuraSpeechEngineCapabilities]; the
/// strict registry below accepts only engines whose data path is verified to
/// remain on-device.
abstract interface class NeuraSpeechEngine {
  String get id;
  NeuraSpeechEngineCapabilities get capabilities;
  Stream<NeuraSpeechSegment> get segments;
  bool get isListening;

  Future<bool> isAvailable();
  Future<bool> start();
  Future<String> stop();
}

final class NeuraSpeechEngineCapabilities {
  const NeuraSpeechEngineCapabilities({
    required this.onDevice,
    required this.supportsPartialResults,
    required this.supportsConfidence,
    required this.supportedPlatforms,
    this.experimental = false,
  });

  final bool onDevice;
  final bool supportsPartialResults;
  final bool supportsConfidence;
  final Set<String> supportedPlatforms;
  final bool experimental;
}

final class NeuraSpeechSegment {
  NeuraSpeechSegment({
    required this.engineId,
    required this.text,
    required this.isFinal,
    required this.observedAtUtc,
    this.confidence,
    this.pauseBefore = Duration.zero,
  }) {
    if (engineId.isEmpty || engineId.length > 128) {
      throw const FormatException('Invalid speech engine ID.');
    }
    if (text.length > 16384 ||
        text.codeUnits.any((unit) => unit == 0 || unit == 0x7f)) {
      throw const FormatException('Invalid speech segment.');
    }
    if (!observedAtUtc.isUtc) {
      throw const FormatException('Speech segment time must be UTC.');
    }
    if (confidence != null &&
        (!confidence!.isFinite || confidence! < 0 || confidence! > 1)) {
      throw const FormatException('Invalid speech confidence.');
    }
    if (pauseBefore.isNegative) {
      throw const FormatException('Invalid speech pause.');
    }
  }

  final String engineId;
  final String text;
  final bool isFinal;
  final DateTime observedAtUtc;
  final double? confidence;
  final Duration pauseBefore;
}

/// Strict local-only registry so platform selection and benchmarking do not
/// leak provider details or accidentally admit an OS-managed cloud recognizer.
final class NeuraSpeechEngineRegistry {
  final Map<String, NeuraSpeechEngine> _engines = {};

  Iterable<NeuraSpeechEngine> get engines => _engines.values;

  void register(NeuraSpeechEngine engine) {
    if (!engine.capabilities.onDevice) {
      throw StateError('Neura accepts only on-device speech engines.');
    }
    if (_engines.containsKey(engine.id)) {
      throw StateError('Speech engine already registered: ${engine.id}');
    }
    _engines[engine.id] = engine;
  }

  Future<NeuraSpeechEngine?> select({
    required String platform,
    String? preferredId,
    bool includeExperimental = false,
  }) async {
    final candidates = [
      if (preferredId != null && _engines[preferredId] != null)
        _engines[preferredId]!,
      ..._engines.values.where((engine) => engine.id != preferredId),
    ];
    for (final engine in candidates) {
      final capabilities = engine.capabilities;
      if (!capabilities.supportedPlatforms.contains(platform) ||
          (capabilities.experimental && !includeExperimental)) {
        continue;
      }
      if (await engine.isAvailable()) return engine;
    }
    return null;
  }
}
