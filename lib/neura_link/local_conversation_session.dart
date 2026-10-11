import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../reliability/safe_boot.dart';
import '../startup/neura_error_pipeline.dart';

enum LocalConversationState {
  disabled,
  starting,
  idle,
  working,
  error,
  unavailable,
  blocked,
}

/// An explicit, foreground typed-text grant. The native owner chooses all paths
/// and owns the model process. This interface has no source, tool or cloud API.
class LocalConversationSession extends ChangeNotifier
    with WidgetsBindingObserver {
  LocalConversationSession({
    MethodChannel channel = const MethodChannel('neura/local_conversation'),
    ValueListenable<bool>? safeMode,
    ValueListenable<NeuraFatalError?>? recovery,
    bool? supported,
  })  : _channel = channel,
        _safeMode = safeMode ?? SafeBoot.instance.safeMode,
        _recovery = recovery ?? NeuraErrorPipeline.instance.fatalError,
        supported = supported ??
            (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.windows &&
                const bool.fromEnvironment('NEURA_ENABLE_OFFLINE_TEXT')) {
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _safeMode.addListener(_onSafety);
    _recovery.addListener(_onSafety);
    _onSafety();
  }

  final MethodChannel _channel;
  final ValueListenable<bool> _safeMode;
  final ValueListenable<NeuraFatalError?> _recovery;
  final bool supported;
  LocalConversationState _state = LocalConversationState.disabled;
  LocalConversationState get state => _state;
  bool _foreground = true;
  bool _blocked = false;
  bool _disposed = false;
  bool _stopConfirmed = true;
  int _epoch = 0;
  Timer? _pollTimer;
  Timer? _deadline;
  Completer<String?>? _reply;
  Future<void> _channelTail = Future<void>.value();

  bool get canStart =>
      supported &&
      !_disposed &&
      !_blocked &&
      _stopConfirmed &&
      _foreground &&
      (_state == LocalConversationState.disabled ||
          _state == LocalConversationState.error ||
          _state == LocalConversationState.unavailable);
  bool get canSend =>
      supported &&
      !_disposed &&
      !_blocked &&
      _foreground &&
      _state == LocalConversationState.idle &&
      _reply == null;
  bool _current(int epoch) =>
      !_disposed && !_blocked && _foreground && epoch == _epoch;

  // Serialize polls, submissions and teardown. A delayed idle poll cannot
  // consume a replacement turn, and Start cannot overtake a pending Stop.
  Future<T?> _call<T>(String method, {Object? argument, required int epoch}) {
    final result = _channelTail.then(
      (_) => _current(epoch)
          ? _channel
              .invokeMethod<T>(method, argument)
              .timeout(const Duration(seconds: 5))
          : Future<T?>.value(),
    );
    _channelTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _update(LocalConversationState next) {
    _state = next;
    if (!_disposed) notifyListeners();
  }

  static LocalConversationState _decode(Object? name) => switch (name) {
        'disabled' => LocalConversationState.disabled,
        'starting' => LocalConversationState.starting,
        'idle' => LocalConversationState.idle,
        'working' => LocalConversationState.working,
        'unavailable' => LocalConversationState.unavailable,
        'blocked' => LocalConversationState.blocked,
        _ => LocalConversationState.error,
      };

  Future<void> start() async {
    if (!canStart) return;
    final epoch = ++_epoch;
    _update(LocalConversationState.starting);
    if (!_current(epoch)) return;
    _deadline?.cancel();
    _deadline = Timer(
      const Duration(seconds: 180),
      () => unawaited(_fail(epoch, LocalConversationState.error)),
    );
    try {
      final state = _decode(await _call<String>('start', epoch: epoch));
      if (!_current(epoch)) return;
      _update(state);
      if (!_current(epoch)) return;
      if (state != LocalConversationState.starting &&
          state != LocalConversationState.idle) {
        await _fail(epoch, state);
      } else {
        if (state == LocalConversationState.idle) _deadline?.cancel();
        _schedulePoll(epoch);
      }
    } catch (_) {
      await _fail(epoch, LocalConversationState.error);
    }
  }

  Future<String?> reply(String text) {
    if (!canSend ||
        text.length > 2048 ||
        text.trim().isEmpty ||
        utf8.encode(text).length > 2048) {
      return Future<String?>.value();
    }
    final epoch = ++_epoch;
    _pollTimer?.cancel();
    final completer = Completer<String?>();
    _reply = completer;
    _update(LocalConversationState.working);
    if (!_current(epoch)) return completer.future;
    _deadline?.cancel();
    _deadline = Timer(
      const Duration(seconds: 120),
      () => unawaited(_fail(epoch, LocalConversationState.error)),
    );
    unawaited(_submit(epoch, text));
    return completer.future;
  }

  Future<void> _submit(int epoch, String text) async {
    try {
      final accepted = await _call<bool>('send', argument: text, epoch: epoch);
      if (_current(epoch)) {
        if (accepted != true) {
          await _fail(epoch, LocalConversationState.error);
        } else {
          _schedulePoll(epoch);
        }
      }
    } catch (_) {
      await _fail(epoch, LocalConversationState.error);
    }
  }

  void _schedulePoll(int epoch) {
    if (!_current(epoch)) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(
      _state == LocalConversationState.idle
          ? const Duration(seconds: 1)
          : const Duration(milliseconds: 100),
      () => unawaited(_poll(epoch)),
    );
  }

  Future<void> _poll(int epoch) async {
    if (!_current(epoch)) return;
    try {
      final snapshot = await _call<Map<Object?, Object?>>('poll', epoch: epoch);
      if (!_current(epoch)) return;
      final next = _decode(snapshot?['state']);
      final text = snapshot?['text'];
      if (text != null &&
          (text is! String ||
              text.isEmpty ||
              text.length > 4096 ||
              utf8.encode(text).length > 4096 ||
              next != LocalConversationState.idle ||
              _reply == null)) {
        await _fail(epoch, LocalConversationState.error);
        return;
      }
      if (next != LocalConversationState.idle &&
          next != LocalConversationState.starting &&
          next != LocalConversationState.working) {
        await _fail(epoch, next);
        return;
      }
      if (_reply != null &&
          next == LocalConversationState.idle &&
          text == null) {
        await _fail(epoch, LocalConversationState.error);
        return;
      }
      if (text is String) {
        // Flutter displays plain text; it never parses output as tool commands.
        _finishReply(
          text.replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), ''),
        );
      }
      if (next == LocalConversationState.idle) _deadline?.cancel();
      _update(next);
      _schedulePoll(epoch);
    } catch (_) {
      await _fail(epoch, LocalConversationState.error);
    }
  }

  void _finishReply(String? text) {
    final reply = _reply;
    _reply = null;
    if (reply != null && !reply.isCompleted) reply.complete(text);
  }

  Future<void> _fail(int epoch, LocalConversationState state) async {
    if (!_current(epoch)) return;
    await stop();
    if (!_disposed && !_blocked && epoch + 1 == _epoch) _update(state);
  }

  Future<void> stop() async {
    final epoch = ++_epoch;
    _pollTimer?.cancel();
    _deadline?.cancel();
    _finishReply(null);
    _stopConfirmed = false;
    _update(
      _blocked
          ? LocalConversationState.blocked
          : LocalConversationState.disabled,
    );
    if (!supported) {
      _stopConfirmed = true;
      return;
    }
    try {
      // Safety teardown is sent immediately, without waiting for a delayed
      // poll response. Invalidation prevents any queued text from being sent.
      await _channel
          .invokeMethod<void>(_blocked ? 'block' : 'stop')
          .timeout(const Duration(seconds: 5));
      if (epoch != _epoch) return;
      _stopConfirmed = true;
      if (!_disposed) notifyListeners();
    } catch (_) {
      if (epoch != _epoch) return;
      // Unconfirmed ownership teardown forbids a new local grant for this view.
      _blocked = true;
      _update(LocalConversationState.blocked);
    }
  }

  void _onSafety() {
    if (_safeMode.value || _recovery.value != null) {
      _blocked = true;
      unawaited(stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeMode.removeListener(_onSafety);
    _recovery.removeListener(_onSafety);
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
