import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../reliability/safe_boot.dart';
import '../startup/neura_error_pipeline.dart';
import 'neura_generation_cancel.dart';
import 'neura_offline_budget.dart';

enum NeuraOllamaModelReadiness {
  unchecked,
  verified,
  notInstalled,
  remote,
  mismatch,
  malformed,
  unreachable,
}

/// Point-in-time prerequisites, never an inference or audio acceptance result.
class NeuraOllamaReadiness {
  const NeuraOllamaReadiness._(
    this.daemonAvailable,
    this.versionSupported,
    this.model,
    this.memory,
  );

  final bool daemonAvailable;
  final bool? versionSupported;
  final NeuraOllamaModelReadiness model;
  final NeuraOfflineMemory? memory;

  bool get ready =>
      daemonAvailable &&
      versionSupported == true &&
      model == NeuraOllamaModelReadiness.verified &&
      memory?.admitted == true;

  static NeuraOllamaReadiness? fromNative(Map<String, dynamic> values) {
    const keys = {
      'version',
      'daemon',
      'daemonVersion',
      'model',
      'memory',
      'totalMiB',
      'availableMiB',
    };
    if (values.length != keys.length ||
        !values.keys.every(keys.contains) ||
        values.values.any((v) => v is! int || v < 0) ||
        values['version'] != 1) {
      return null;
    }
    final daemon = values['daemon'] as int;
    final version = values['daemonVersion'] as int;
    final model = values['model'] as int;
    final admission = values['memory'] as int;
    final total = values['totalMiB'] as int;
    final available = values['availableMiB'] as int;
    if (!((daemon == 2 && version == 0 && model == 0) ||
            (daemon == 1 && version == 2 && model == 0) ||
            (daemon == 1 && version == 1 && model >= 1 && model <= 6)) ||
        admission > 2 ||
        available > total ||
        (admission == 0 && (total != 0 || available != 0)) ||
        (admission != 0 && total == 0)) {
      return null;
    }
    final memory = admission == 0 ? null : NeuraOfflineMemory(total, available);
    if (memory != null && memory.admitted != (admission == 1)) return null;
    return NeuraOllamaReadiness._(
      daemon == 1,
      version == 0 ? null : version == 1,
      NeuraOllamaModelReadiness.values[model],
      memory,
    );
  }
}

enum NeuraOllamaLatencyOutcome { running, delivered, failed, cancelled }

/// Latest request only, held in RAM. No text, credentials, timestamps or IDs.
/// Native delivery ends at the native poll copy; total ends at Dart return.
/// Cancellation measures Neura cleanup, not daemon/GPU compute cessation.
class NeuraOllamaLatency {
  const NeuraOllamaLatency({
    required this.outcome,
    this.total,
    this.cancellation,
    this.preflight,
    this.inference,
    this.delivery,
    this.nativeCancellation,
    this.nativeTotal,
  });

  final NeuraOllamaLatencyOutcome outcome;
  final Duration? total;
  final Duration? cancellation;
  final Duration? preflight;
  final Duration? inference;
  final Duration? delivery;
  final Duration? nativeCancellation;
  final Duration? nativeTotal;
}

class _LatencyTurn {
  _LatencyTurn(this.started);
  final Duration started;
  int? nativeId;
  Duration? cancelAt;
  Duration? total;
  Duration? cancellation;
  NeuraOllamaLatencyOutcome outcome = NeuraOllamaLatencyOutcome.running;
}

/// One tool call the local model requested. Running it still requires the
/// room policy check and the user's confirmation in the AI service.
class NeuraOllamaToolCall {
  const NeuraOllamaToolCall(this.name, this.arguments);
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};
}

/// A reply to a request that advertised tools: text plus any tool calls.
class NeuraOllamaTurn {
  const NeuraOllamaTurn(this.text, this.toolCalls);
  final String text;
  final List<NeuraOllamaToolCall> toolCalls;

  static final _toolName = RegExp(r'^[a-z_]{1,40}$');

  /// Tool results enter the small offline context: keep the newest whole
  /// lines within [maxBytes] (mood history lists oldest first).
  static String boundToolResult(String result, {int maxBytes = 1500}) {
    if (utf8.encode(result).length <= maxBytes) return result;
    final kept = <String>[];
    var bytes = 0;
    for (final line in result.split('\n').reversed) {
      final size = utf8.encode(line).length + 1;
      if (bytes + size > maxBytes) break;
      bytes += size;
      kept.insert(0, line);
    }
    return kept.isEmpty
        ? 'Tool result was too long to share.'
        : kept.join('\n');
  }

  /// Strict schema; anything unexpected is a failed reply, never guessed.
  static NeuraOllamaTurn parse(String envelope) {
    final value = jsonDecode(envelope);
    if (value is! Map ||
        value.length != 2 ||
        value['text'] is! String ||
        value['tool_calls'] is! List) {
      throw const FormatException('Invalid offline tool reply.');
    }
    final calls = <NeuraOllamaToolCall>[];
    for (final call in value['tool_calls'] as List) {
      if (call is! Map ||
          call.length != 2 ||
          call['name'] is! String ||
          !_toolName.hasMatch(call['name'] as String) ||
          call['arguments'] is! Map) {
        throw const FormatException('Invalid offline tool call.');
      }
      calls.add(NeuraOllamaToolCall(
        call['name'] as String,
        Map<String, dynamic>.from(call['arguments'] as Map),
      ));
    }
    return NeuraOllamaTurn(value['text'] as String, calls);
  }
}

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

  /// Offline history is drawn from the visible transcript, so this matches
  /// NeuraOfflineBudget.maxTurns.
  static const maxVisibleMessages = 16;
  static const maxVisibleBytes = 16384;

  /// Largest request accepted natively (charter, history, tools).
  static const maxRequestBytes = 24576;

  /// Largest per-turn cue accepted natively.
  static const maxCueBytes = 512;

  /// Poll cadence for the native worker. Short enough that streamed text and
  /// the final reply reach Dart promptly; each poll is a cheap in-process copy.
  static const pollInterval = Duration(milliseconds: 20);

  /// Drop whole oldest messages; keep the newest bounded reply visible.
  /// The model's separate 1500-byte context limit remains enforced in Rust.
  static int firstRetainedVisibleMessage(List<String> messages) {
    var bytes = messages.fold<int>(
      0,
      (sum, text) => sum + utf8.encode(text).length,
    );
    var first = 0;
    while (messages.length - first > 1 &&
        (messages.length - first > maxVisibleMessages ||
            bytes > maxVisibleBytes)) {
      bytes -= utf8.encode(messages[first++]).length;
    }
    return first;
  }

  NeuraOllamaChat({
    MethodChannel channel = const MethodChannel(
      'neura/engine_synthetic_session',
    ),
    ValueListenable<bool>? safeMode,
    ValueListenable<bool>? restartRequired,
    ValueListenable<NeuraFatalError?>? recovery,
    bool? supported,
    Duration Function()? monotonicNow,
  })  : _channel = channel,
        _monotonicNow = monotonicNow,
        _safeMode = safeMode ?? SafeBoot.instance.safeMode,
        _restartRequired = restartRequired ?? SafeBoot.instance.restartRequired,
        _recovery = recovery ?? NeuraErrorPipeline.instance.fatalError,
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _safeMode.addListener(_onSafetyChanged);
    _restartRequired.addListener(_onSafetyChanged);
    _recovery.addListener(_onSafetyChanged);
    _onSafetyChanged();
  }

  final MethodChannel _channel;
  final ValueListenable<bool> _safeMode;
  final ValueListenable<bool> _restartRequired;
  final ValueListenable<NeuraFatalError?> _recovery;
  final bool _supported;
  final Duration Function()? _monotonicNow;
  final Stopwatch _latencyClock = Stopwatch()..start();
  _LatencyTurn? _latestLatency;
  Duration get _now => _monotonicNow?.call() ?? _latencyClock.elapsed;
  bool _foreground = true;
  bool _blocked = false;
  bool _disposed = false;
  NeuraGenerationCancel? _active;

  bool get _allowed => _supported && !_blocked && !_disposed && _foreground;

  /// User-triggered metadata only. Reuses the Rust model verifier and worker;
  /// never sends conversation text, loads weights or starts a voice session.
  Future<NeuraOllamaReadiness> checkReadiness({
    required NeuraGenerationCancel cancel,
  }) async {
    if (!_supported) {
      throw StateError(
        'Offline Ollama readiness is available on Windows only.',
      );
    }
    if (!_allowed) {
      throw StateError(
        'Readiness check is blocked. Keep Neura in the foreground; '
        'Safe Mode and recovery require an app restart.',
      );
    }
    if (_active != null) {
      throw StateError(
        'Stop the current offline request before checking readiness.',
      );
    }
    cancel.throwIfCancelled();
    _active = cancel;
    int? nativeId;
    var finished = false;
    try {
      // Await even if cancelled: receive and revoke any late native id.
      nativeId = await _channel.invokeMethod<int>('beginOllamaReadiness');
      if (nativeId == null || nativeId <= 0) {
        throw StateError('Check not started.');
      }
      final id = nativeId;
      unawaited(
        cancel.whenCancelled.then((_) async {
          if (!finished) await _cancelNative(id);
        }),
      );
      cancel.throwIfCancelled();
      final clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 12)) {
        if (!_allowed) cancel.cancel();
        cancel.throwIfCancelled();
        final values = await _channel.invokeMapMethod<String, dynamic>(
          'pollOllamaReadiness',
          id,
        );
        cancel.throwIfCancelled();
        if (!_allowed) throw NeuraGenerationCancelled(cancel.generationId);
        if (values != null) {
          final report = NeuraOllamaReadiness.fromNative(values);
          if (report == null) throw StateError('Invalid readiness snapshot.');
          return report;
        }
        await cancel.delay(const Duration(milliseconds: 100));
      }
      throw StateError('Check timed out.');
    } on NeuraGenerationCancelled {
      rethrow;
    } catch (_) {
      cancel.throwIfCancelled();
      throw StateError(
        'Readiness check unavailable or timed out. Stop any offline '
        'reply, keep Neura in the foreground and use an updated Windows build. '
        'No model was loaded or downloaded.',
      );
    } finally {
      finished = true;
      if (nativeId != null) await _cancelNative(nativeId);
      if (identical(_active, cancel)) _active = null;
      cancel.throwIfCancelled();
      if (!_allowed) throw NeuraGenerationCancelled(cancel.generationId);
    }
  }

  /// Explicit read only. Does not poll, start inference, log or save a sample.
  /// Missing phases remain null, including an unfinished cancellation cleanup.
  Future<NeuraOllamaLatency?> readLatency() async {
    final turn = _latestLatency;
    if (!_allowed || turn == null) return null;
    Map<String, dynamic>? native;
    if (turn.nativeId != null) {
      try {
        native = await _channel.invokeMapMethod<String, dynamic>(
          'readOllamaTiming',
          turn.nativeId,
        );
      } catch (_) {
        // Timing is optional; instrumentation never changes reply behavior.
      }
    }
    if (!_allowed || !identical(turn, _latestLatency)) return null;
    if (turn.nativeId != null && native == null) return null;
    const keys = {
      'version',
      'outcome',
      'preflightUs',
      'inferenceUs',
      'deliveryUs',
      'cancellationUs',
      'totalUs',
    };
    if (native != null &&
        (native.length != keys.length ||
            !native.keys.every(keys.contains) ||
            native['version'] != 1 ||
            native['outcome'] is! int ||
            (native['outcome'] as int) < 0 ||
            (native['outcome'] as int) > 4 ||
            native.values.any(
              (value) => value != null && (value is! int || value < 0),
            ))) {
      return null;
    }
    Duration? phase(String key) {
      final value = native?[key];
      return value is int ? Duration(microseconds: value) : null;
    }

    return NeuraOllamaLatency(
      outcome: turn.outcome,
      total: turn.total,
      cancellation: turn.cancellation,
      preflight: phase('preflightUs'),
      inference: phase('inferenceUs'),
      delivery: phase('deliveryUs'),
      nativeCancellation: phase('cancellationUs'),
      nativeTotal: phase('totalUs'),
    );
  }

  void clearLatency() {
    _latestLatency = null;
    if (_supported) {
      unawaited(
        _channel.invokeMethod<void>('clearOllamaTiming').catchError((_) {}),
      );
    }
  }

  /// Returns the complete, natively verified reply. With [onPartial], the text
  /// streamed so far is also reported as it grows (each call a longer prefix),
  /// so callers can display and speak a reply before generation finishes.
  /// Partial text is unverified until this future completes.
  ///
  /// [cue] is a short per-turn note (at most [maxCueBytes]). It is sent after
  /// the newest turn rather than inside [system], so the charter and earlier
  /// turns stay identical between turns and Ollama reuses their cached prompt
  /// evaluation instead of re-reading the whole conversation every turn.
  Future<String> reply({
    required String system,
    required List<Map<String, dynamic>> messages,
    required NeuraGenerationCancel cancel,
    void Function(String textSoFar)? onPartial,
    List<Map<String, dynamic>> tools = const [],
    String cue = '',
  }) async {
    if (!_allowed) throw StateError('Offline chat is unavailable.');
    cancel.throwIfCancelled();
    final started = _now;
    final payload = jsonEncode({
      'system': system,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      if (cue.trim().isNotEmpty) 'cue': cue,
    });
    if (utf8.encode(payload).length > maxRequestBytes) {
      throw StateError('This conversation is too large for offline chat.');
    }
    _active?.cancel();
    _active = cancel;
    final timing = _LatencyTurn(started);
    _latestLatency = timing;
    int? nativeId;
    var finished = false;
    var delivered = false;
    unawaited(
      cancel.whenCancelled.then((_) {
        if (timing.total == null) timing.cancelAt ??= _now;
      }),
    );
    try {
      // Keep this awaited: cancellation before the start reply must still
      // receive and cancel the native id instead of orphaning native work.
      nativeId = await _channel.invokeMethod<int>('beginOllama', payload);
      if (nativeId == null || nativeId <= 0) {
        throw StateError('Offline chat could not start.');
      }
      final id = nativeId;
      timing.nativeId = id;
      unawaited(
        cancel.whenCancelled.then((_) async {
          if (!finished) await _cancelNative(id);
        }),
      );
      cancel.throwIfCancelled();
      final clock = Stopwatch()..start();
      var peeking = onPartial != null;
      var reported = 0;
      // Slightly longer than the native 300 s reply deadline, so the native
      // owner reports the outcome. Replies stream throughout this time.
      while (clock.elapsed < const Duration(seconds: 305)) {
        if (!_allowed) cancel.cancel();
        cancel.throwIfCancelled();
        final text = await _channel.invokeMethod<String>('pollOllama', id);
        cancel.throwIfCancelled();
        if (!_allowed) throw NeuraGenerationCancelled(cancel.generationId);
        if (text != null) {
          delivered = true;
          return text;
        }
        if (peeking) {
          String? partial;
          try {
            partial = await _channel.invokeMethod<String>('peekOllama', id);
          } on MissingPluginException {
            peeking = false; // Older runner: complete replies only.
          }
          cancel.throwIfCancelled();
          if (!_allowed) throw NeuraGenerationCancelled(cancel.generationId);
          if (partial != null && partial.length > reported) {
            reported = partial.length;
            onPartial!(partial);
          }
        }
        await cancel.delay(pollInterval);
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
      final now = _now;
      timing.total = now - timing.started;
      if (timing.cancelAt != null) timing.cancellation = now - timing.cancelAt!;
      timing.outcome = cancel.isCancelled || !_allowed
          ? NeuraOllamaLatencyOutcome.cancelled
          : delivered
              ? NeuraOllamaLatencyOutcome.delivered
              : NeuraOllamaLatencyOutcome.failed;
      if (identical(_active, cancel)) _active = null;
      // A safety/lifecycle cancellation during final native cleanup must also
      // suppress a previously polled reply before returning it to the caller.
      if (delivered) {
        cancel.throwIfCancelled();
        if (!_allowed) throw NeuraGenerationCancelled(cancel.generationId);
      }
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
    if (!_safeMode.value &&
        !_restartRequired.value &&
        _recovery.value == null) {
      return;
    }
    _blocked = true;
    clearLatency();
    _active?.cancel();
    if (_supported) {
      unawaited(_channel.invokeMethod<void>('blockOllama').catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _active?.cancel();
      clearLatency();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clearLatency();
    _active?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _safeMode.removeListener(_onSafetyChanged);
    _restartRequired.removeListener(_onSafetyChanged);
    _recovery.removeListener(_onSafetyChanged);
  }
}
