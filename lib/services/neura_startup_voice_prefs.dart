import 'package:flutter/foundation.dart';

import '../startup/neura_prefs_cache.dart';

/// One explicit device-local opt-in, independent of ambient clip recording.
class NeuraStartupVoicePrefs {
  NeuraStartupVoicePrefs._();
  @visibleForTesting
  NeuraStartupVoicePrefs.forTesting();
  static final instance = NeuraStartupVoicePrefs._();
  static const key = 'neura.voice.on_startup.v1';
  final enabled = ValueNotifier(false);
  Future<void>? _pending;
  bool _suspended = false;
  int _revision = 0;

  Future<void> init() async {
    enabled.value = NeuraPrefsCache.prefsOrNull?.getBool(key) ?? false;
  }

  Future<void> setEnabled(bool value) {
    if (_suspended) {
      return Future.error(StateError('Restart Neura after data removal.'));
    }
    final revision = ++_revision;
    if (!value) enabled.value = false;
    final operation = (_pending ?? Future<void>.value()).then((_) async {
      if (_suspended) return;
      final saved = await NeuraPrefsCache.prefs.setBool(key, value);
      if (!saved) throw StateError('Startup voice preference was not saved.');
      if (!_suspended && revision == _revision) enabled.value = value;
    });
    late final Future<void> tail;
    tail = operation.catchError((Object _) {}).whenComplete(() {
      if (identical(_pending, tail)) _pending = null;
    });
    _pending = tail;
    return operation;
  }

  void resetAfterDataWipe() {
    _suspended = true;
    _revision++;
    enabled.value = false;
  }

  /// Preferences must not be cleared underneath a submitted platform write.
  Future<void> drainForDataWipe() async {
    await _pending?.timeout(const Duration(seconds: 3));
  }
}
