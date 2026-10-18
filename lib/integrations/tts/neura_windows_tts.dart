import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Windows-only local SAPI channel. Never falls back to flutter_tts's Windows
/// speak/coroutine implementation. No text is returned by the polling protocol.
class NeuraWindowsTts extends FlutterTts {
  NeuraWindowsTts({
    MethodChannel channel = const MethodChannel('neura/speech_synthesis'),
    Duration commandTimeout = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 40),
  })  : _channel = channel,
        _commandTimeout = commandTimeout,
        _pollInterval = pollInterval;

  final MethodChannel _channel;
  final Duration _commandTimeout;
  final Duration _pollInterval;
  Timer? _timer;
  int _serial = 0;
  int? _active;
  bool _polling = false;
  bool _failed = false;

  Future<T?> _invoke<T>(String method, [Object? value]) =>
      _channel.invokeMethod<T>(method, value).timeout(_commandTimeout);

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    if (awaitCompletion) {
      throw UnsupportedError('Native completion waiting is disabled.');
    }
    return 1;
  }

  @override
  Future<dynamic> get getVoices => _invoke<List<dynamic>>('getVoices');
  @override
  Future<dynamic> setVoice(Map<String, String> voice) =>
      _invoke<int>('setVoice', voice);
  @override
  Future<dynamic> setSpeechRate(double rate) =>
      _invoke<int>('setSpeechRate', rate);
  @override
  Future<dynamic> setPitch(double pitch) => _invoke<int>('setPitch', pitch);
  @override
  Future<dynamic> setVolume(double volume) => _invoke<int>('setVolume', volume);

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    if (_failed) {
      throw StateError('Local speech requires an application restart.');
    }
    if (text.isEmpty ||
        text.length > 65536 ||
        text.contains('\u0000') ||
        utf8.encode(text).length > 65536) {
      throw ArgumentError('Local speech text is outside the supported bounds.');
    }
    if (_active != null) throw StateError('Stop the current speech first.');
    final id = ++_serial;
    _active = id;
    try {
      final accepted = await _invoke<int>('speak', {'id': id, 'text': text});
      if (_active != id) return 0;
      if (accepted != 1) {
        _clear();
        return 0;
      }
      startHandler?.call();
      if (_active == id) {
        _timer = Timer.periodic(_pollInterval, (_) => unawaited(_poll(id)));
      }
      return 1;
    } catch (_) {
      _failed = true;
      if (_active == id) {
        _clear();
        // A late native acknowledgement could otherwise leave audio running
        // after the caller has already failed. This purge is best effort and
        // bounded; it cannot interrupt a blocked native UI thread.
        try {
          await _invoke<int>('stop');
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _poll(int id) async {
    if (_polling || _active != id) return;
    _polling = true;
    try {
      final reply = await _invoke<Map<dynamic, dynamic>>('poll');
      if (_active != id) return;
      if (reply == null || reply['id'] != id) {
        throw StateError('Local speech returned an invalid request identity.');
      }
      switch (reply['state']) {
        case 'speaking':
          return;
        case 'completed':
          _clear();
          completionHandler?.call();
        case 'cancelled':
          _clear();
          cancelHandler?.call();
        default:
          throw StateError('Local speech returned an invalid state.');
      }
    } catch (_) {
      if (_active != id) return;
      _failed = true;
      _timer?.cancel();
      try {
        await _invoke<int>('stop');
      } catch (_) {}
      if (_active != id) return;
      _clear();
      errorHandler?.call('Local speech failed.');
    } finally {
      _polling = false;
    }
  }

  void _clear() {
    _timer?.cancel();
    _timer = null;
    _active = null;
  }

  @override
  Future<dynamic> stop() async {
    // Revoke identity before awaiting native work. Old poll/acknowledgement
    // results cannot complete a replacement, including after a Safe Mode exit.
    final stopped = _active;
    _clear();
    bool ownsSignal() =>
        stopped != null && _serial == stopped && _active == null;
    final int? result;
    try {
      result = await _invoke<int>('stop');
    } catch (_) {
      _failed = true;
      if (ownsSignal()) errorHandler?.call('Local speech failed.');
      rethrow;
    }
    if (result != 1) {
      _failed = true;
      if (ownsSignal()) errorHandler?.call('Local speech failed.');
    } else if (ownsSignal()) {
      cancelHandler?.call();
    }
    return result;
  }
}
