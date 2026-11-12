import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../profiles/local_profile_service.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import 'neura_teaching_preferences.dart';
import 'neura_teaching_store.dart';

export 'neura_teaching_store.dart';

/// A single direct edit gesture. This grants no memory or action permission.
class NeuraTeachingPermit {
  NeuraTeachingPermit._(this._owner, this._epoch, this._revision, this._issued);
  final NeuraTeachingService _owner;
  final int _epoch;
  final int _revision;
  final DateTime _issued;
  bool _used = false;
  bool _revoked = false;
  void revoke() => _revoked = true;
  bool get valid => _owner._valid(this);
}

/// Two opt-in, enum-only local settings for one ordinary installation.
/// Never reads transcripts/journals, infers facts, or mints memory grants.
class NeuraTeachingService extends ChangeNotifier with WidgetsBindingObserver {
  NeuraTeachingService._({
    required NeuraTeachingStore store,
    DateTime Function()? now,
    bool Function()? profileMode,
    bool requirePreferences = true,
  })  : _store = store,
        _now = now ?? DateTime.now,
        _profileMode =
            profileMode ?? (() => LocalProfileService.instance.enabled),
        _requirePreferences = requirePreferences {
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
    LocalProfileService.instance.addListener(_onProfile);
    _owners.add(this);
  }

  @visibleForTesting
  factory NeuraTeachingService.forTesting({
    required NeuraTeachingStore store,
    DateTime Function()? now,
    bool Function()? profileMode,
  }) =>
      NeuraTeachingService._(
          store: store,
          now: now,
          profileMode: profileMode,
          requirePreferences: false);

  static final instance =
      NeuraTeachingService._(store: NeuraEncryptedTeachingStore());
  static final _owners = <NeuraTeachingService>{};
  static final _active = <Future<void>>{};
  static bool _wipeSuspended = false;
  @visibleForTesting
  static Duration wipeDrainTimeout = const Duration(seconds: 30);

  static void suspendAllForDataWipe() {
    _wipeSuspended = true;
    for (final owner in _owners.toList()) {
      owner._invalidate();
    }
  }

  static Future<void> drainAllForDataWipe() =>
      Future.wait(_active.toList()).timeout(wipeDrainTimeout);

  @visibleForTesting
  static void resetWipeGateForTesting() {
    if (_active.isNotEmpty)
      throw StateError('Teaching storage is still active.');
    _wipeSuspended = false;
    wipeDrainTimeout = const Duration(seconds: 30);
    for (final owner in _owners.toList()) {
      owner._invalidate();
    }
  }

  final NeuraTeachingStore _store;
  final DateTime Function() _now;
  final bool Function() _profileMode;
  final bool _requirePreferences;
  NeuraTeachingPreferences _saved = const NeuraTeachingPreferences();
  NeuraTeachingPreferences _today = const NeuraTeachingPreferences();
  DateTime? _todayDate;
  Timer? _expiry;
  bool _loaded = false;
  bool _busy = false;
  bool _disposed = false;
  bool _foreground = true;
  int _epoch = 0;
  int _revision = 0;
  Future<void>? _loading;
  String? _error;

  bool get available =>
      !_disposed &&
      !_wipeSuspended &&
      (!_requirePreferences || NeuraPrefsCache.prefsOrNull != null) &&
      !_profileMode() &&
      _foreground &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;
  bool get loaded => _loaded && available && _store.authorityCurrent;
  bool get busy => _busy;
  String? get error => _error;
  NeuraTeachingPreferences get saved =>
      loaded ? _saved : const NeuraTeachingPreferences();
  bool get _todayCurrent {
    final now = _now();
    final date = _todayDate;
    return loaded &&
        date != null &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool get answerIsTemporary => _todayCurrent && _today.answerDetail != null;
  bool get planIsTemporary => _todayCurrent && _today.planSize != null;
  NeuraTeachingPreferences get current => NeuraTeachingPreferences(
        answerDetail:
            answerIsTemporary ? _today.answerDetail : saved.answerDetail,
        planSize: planIsTemporary ? _today.planSize : saved.planSize,
      );

  void _check() {
    if (!available) throw StateError('Teach Neura is unavailable right now.');
  }

  Future<void> _track(Future<void> Function() work) {
    final operation = Future<void>.sync(work);
    final drained =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _active.add(drained);
    unawaited(drained.whenComplete(() => _active.remove(drained)));
    return operation;
  }

  Future<void> load() {
    _check();
    if (loaded) return Future.value();
    final loading = _loading;
    if (loading != null) return loading;
    if (_busy) return Future.error(StateError('Teaching storage is busy.'));
    final epoch = _epoch;
    _busy = true;
    final operation = _track(() async {
      try {
        final value =
            await _store.read(stillAllowed: () => available && epoch == _epoch);
        _check();
        if (epoch != _epoch) throw StateError('Teaching load was cancelled.');
        _saved = value;
        _loaded = true;
        _error = null;
      } catch (_) {
        _loaded = false;
        _saved = const NeuraTeachingPreferences();
        _error = 'Saved preferences could not be loaded. Nothing was replaced.';
        rethrow;
      } finally {
        _busy = false;
        _loading = null;
        if (!_disposed) notifyListeners();
      }
    });
    _loading = operation;
    return operation;
  }

  NeuraTeachingPermit beginChange({required bool directUserGesture}) {
    _check();
    if (!directUserGesture || !loaded || _busy) {
      throw StateError('Review the current preferences before changing them.');
    }
    return NeuraTeachingPermit._(this, _epoch, _revision, _now());
  }

  bool _valid(NeuraTeachingPermit permit) {
    final now = _now();
    return available &&
        _store.authorityCurrent &&
        identical(permit._owner, this) &&
        !permit._revoked &&
        permit._epoch == _epoch &&
        permit._revision == _revision &&
        now.year == permit._issued.year &&
        now.month == permit._issued.month &&
        now.day == permit._issued.day &&
        !now.isBefore(permit._issued) &&
        now.isBefore(permit._issued.add(const Duration(minutes: 5)));
  }

  Future<void> setAnswerDetail(
          NeuraTeachingPermit permit, NeuraAnswerDetail value,
          {required bool today}) =>
      _change(permit, answer: true, value: value, today: today);
  Future<void> setPlanSize(NeuraTeachingPermit permit, NeuraPlanSize value,
          {required bool today}) =>
      _change(permit, answer: false, value: value, today: today);
  Future<void> removeAnswerDetail(NeuraTeachingPermit permit) =>
      _change(permit, answer: true, today: false);
  Future<void> removePlanSize(NeuraTeachingPermit permit) =>
      _change(permit, answer: false, today: false);

  Future<void> _change(NeuraTeachingPermit permit,
      {required bool answer, Enum? value, required bool today}) async {
    if (!_valid(permit) || permit._used || _busy || !loaded) {
      throw StateError('This teaching choice expired. Review it again.');
    }
    permit._used = true;
    final next = answer
        ? _saved.withAnswerDetail(value as NeuraAnswerDetail?)
        : _saved.withPlanSize(value as NeuraPlanSize?);
    if (today) {
      if (!_todayCurrent) _today = const NeuraTeachingPreferences();
      _today = answer
          ? _today.withAnswerDetail(value as NeuraAnswerDetail?)
          : _today.withPlanSize(value as NeuraPlanSize?);
      _todayDate = _now();
      _expiry?.cancel();
      final now = _now();
      final midnight = DateTime(now.year, now.month, now.day + 1);
      _expiry = Timer(midnight.difference(now), () {
        _today = const NeuraTeachingPreferences();
        _todayDate = null;
        _revision++;
        if (!_disposed) notifyListeners();
      });
      _revision++;
      _error = null;
      notifyListeners();
      return;
    }

    _busy = true;
    notifyListeners();
    await _track(() async {
      try {
        await _store.write(next, stillAllowed: () => _valid(permit));
        if (!_valid(permit)) throw StateError('Teaching change was cancelled.');
        _saved = next;
        _today =
            answer ? _today.withAnswerDetail(null) : _today.withPlanSize(null);
        _revision++;
        _error = null;
      } catch (_) {
        // A platform can write then report failure. Drop the cache and require
        // a fresh durable read; never publish an unconfirmed draft or retry it.
        _loaded = false;
        _saved = const NeuraTeachingPreferences();
        _today = const NeuraTeachingPreferences();
        _error =
            'The change could not be confirmed. Review saved preferences before retrying.';
        _revision++;
        rethrow;
      } finally {
        _busy = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  void _invalidate() {
    _epoch++;
    _revision++;
    _loaded = false;
    _saved = const NeuraTeachingPreferences();
    _today = const NeuraTeachingPreferences();
    _todayDate = null;
    _expiry?.cancel();
    if (!_disposed) notifyListeners();
  }

  void _onSafety() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      _invalidate();
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  void _onProfile() {
    if (_profileMode()) _invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidate();
  }

  @override
  void dispose() {
    _invalidate();
    _disposed = true;
    _owners.remove(this);
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    LocalProfileService.instance.removeListener(_onProfile);
    super.dispose();
  }
}
