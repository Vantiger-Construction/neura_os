import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../reliability/safe_boot.dart';
import '../startup/neura_error_pipeline.dart';
import 'neura_generation_cancel.dart';

/// Reject an oversized paste before it enters the offline editor/undo history.
class NeuraOllamaTextInputFormatter extends TextInputFormatter {
  const NeuraOllamaTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      utf8.encode(newValue.text).length <= NeuraOllamaChat.maxInputBytes
          ? newValue
          : oldValue;
}

/// Windows native owner forwards text to Rust; no Dart HTTP or cloud fallback.
class NeuraOllamaChat with WidgetsBindingObserver {
  static const maxInputBytes = 1500;
  static const maxVisibleMessages = 8;
  static const maxVisibleBytes = 16384;

  /// Drop whole oldest messages; keep the newest bounded reply visible.
  /// The model's separate 1500-byte context limit remains enforced in Rust.
  static int firstRetainedVisibleMessage(List<String> messages) {
    var bytes =
        messages.fold<int>(0, (sum, text) => sum + utf8.encode(text).length);
    var first = 0;
    while (messages.length - first > 1 &&
        (messages.length - first > maxVisibleMessages ||
            bytes > maxVisibleBytes)) {
      bytes -= utf8.encode(messages[first++]).length;
    }
    return first;
  }

  NeuraOllamaChat({
    MethodChannel channel =
        const MethodChannel('neura/engine_synthetic_session'),
    ValueListenable<bool>? safeMode,
    ValueListenable<NeuraFatalError?>? recovery,
    bool? supported,
  })  : _channel = channel,
        _safeMode = safeMode ?? SafeBoot.instance.safeMode,
        _recovery = recovery ?? NeuraErrorPipeline.instance.fatalError,
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _safeMode.addListener(_onSafetyChanged);
    _recovery.addListener(_onSafetyChanged);
    _onSafetyChanged();
  }

  final MethodChannel _channel;
  final ValueListenable<bool> _safeMode;
  final ValueListenable<NeuraFatalError?> _recovery;
  final bool _supported;
  bool _foreground = true;
  bool _blocked = false;
  bool _disposed = false;
  NeuraGenerationCancel? _active;

  bool get _allowed => _supported && !_blocked && !_disposed && _foreground;

  Future<String> reply({
    required String system,
    required List<Map<String, dynamic>> messages,
    required NeuraGenerationCancel cancel,
  }) async {
    if (!_allowed) throw StateError('Offline chat is unavailable.');
    cancel.throwIfCancelled();
    final payload = jsonEncode({'system': system, 'messages': messages});
    if (utf8.encode(payload).length > 16384) {
      throw StateError('This conversation is too large for offline chat.');
    }
    _active?.cancel();
    _active = cancel;
    int? nativeId;
    var finished = false;
    try {
      // Keep this awaited: cancellation before the start reply must still
      // receive and cancel the native id instead of orphaning native work.
      nativeId = await _channel.invokeMethod<int>('beginOllama', payload);
      if (nativeId == null || nativeId <= 0) {
        throw StateError('Offline chat could not start.');
      }
      final id = nativeId;
      unawaited(cancel.whenCancelled.then((_) async {
        if (!finished) await _cancelNative(id);
      }));
      cancel.throwIfCancelled();
      final clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 95)) {
        if (!_allowed) cancel.cancel();
        cancel.throwIfCancelled();
        final text = await _channel.invokeMethod<String>('pollOllama', id);
        cancel.throwIfCancelled();
        if (!_allowed) throw NeuraGenerationCancelled(cancel.generationId);
        if (text != null) return text;
        await cancel.delay(const Duration(milliseconds: 100));
      }
      throw StateError('Offline reply timed out.');
    } on NeuraGenerationCancelled {
      rethrow;
    } catch (_) {
      cancel.throwIfCancelled();
      throw StateError(
        'Offline reply unavailable. Open Ollama and install qwen3:4b-instruct. '
        'No cloud request was made.',
      );
    } finally {
      finished = true;
      if (nativeId != null) await _cancelNative(nativeId);
      if (identical(_active, cancel)) _active = null;
    }
  }

  Future<void> _cancelNative(int id) async {
    try {
      await _channel.invokeMethod<void>('cancelOllama', id);
    } catch (_) {
      // Window destruction/background also invalidates the native generation.
    }
  }

  void _onSafetyChanged() {
    if (!_safeMode.value && _recovery.value == null) return;
    _blocked = true;
    _active?.cancel();
    if (_supported) {
      unawaited(_channel.invokeMethod<void>('blockOllama').catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _active?.cancel();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _safeMode.removeListener(_onSafetyChanged);
    _recovery.removeListener(_onSafetyChanged);
  }
}
