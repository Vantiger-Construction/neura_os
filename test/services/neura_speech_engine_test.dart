import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_speech_engine.dart';

final class _Engine implements NeuraSpeechEngine {
  _Engine(
    this.id, {
    required this.platforms,
    this.experimental = false,
    this.available = true,
    this.onDevice = true,
  });

  @override
  final String id;
  final Set<String> platforms;
  final bool experimental;
  final bool available;
  final bool onDevice;

  @override
  NeuraSpeechEngineCapabilities get capabilities =>
      NeuraSpeechEngineCapabilities(
        onDevice: onDevice,
        supportsPartialResults: true,
        supportsConfidence: true,
        supportedPlatforms: platforms,
        experimental: experimental,
      );

  @override
  bool get isListening => false;

  @override
  Stream<NeuraSpeechSegment> get segments => const Stream.empty();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> start() async => true;

  @override
  Future<String> stop() async => '';
}

void main() {
  test('selection keeps experimental engines opt-in', () async {
    final registry = NeuraSpeechEngineRegistry()
      ..register(_Engine(
        'onnx',
        platforms: {'windows'},
        experimental: true,
      ))
      ..register(_Engine('winrt', platforms: {'windows'}));

    expect(
      (await registry.select(platform: 'windows', preferredId: 'onnx'))?.id,
      'winrt',
    );
    expect(
      (await registry.select(
        platform: 'windows',
        preferredId: 'onnx',
        includeExperimental: true,
      ))
          ?.id,
      'onnx',
    );
  });

  test('registry rejects any engine that can upload speech', () {
    final registry = NeuraSpeechEngineRegistry();

    expect(
      () => registry.register(
        _Engine('cloud', platforms: {'windows'}, onDevice: false),
      ),
      throwsStateError,
    );
  });
}

