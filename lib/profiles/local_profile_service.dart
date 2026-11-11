import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../core/memory/memory_crypto.dart';
import '../persona/models/neura_audience.dart';
import '../persona/models/persona_profile.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';
import 'local_profile_runtime.dart';

/// Delivery preferences only. No transcript, inferred facts or permissions.
@immutable
class LocalNeuraProfile {
  const LocalNeuraProfile(
      {required this.id,
      required this.label,
      required this.persona,
      required this.audience});
  final String id;
  final String label;
  final PersonaProfile persona;
  final NeuraAudience audience;

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'persona': persona.toMap(),
        'audience': audience.name
      };

  factory LocalNeuraProfile.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final label = map['label'];
    final persona = map['persona'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(id) ||
        label is! String ||
        label.trim().isEmpty ||
        label.length > 40 ||
        label.codeUnits.any((c) => c < 0x20 || c == 0x7f) ||
        persona is! Map<String, dynamic> ||
        !['warmth', 'directness', 'humor', 'energy', 'depth'].every((key) =>
            persona[key] is num &&
            (persona[key] as num).isFinite &&
            (persona[key] as num) >= 0 &&
            (persona[key] as num) <= 1) ||
        !NeuraAudience.values.any((a) => a.name == map['audience'])) {
      throw const FormatException('Invalid local profile.');
    }
    return LocalNeuraProfile(
        id: id,
        label: label.trim(),
        persona: PersonaProfile.fromMap(persona),
        audience: NeuraAudience.values.byName(map['audience'] as String));
  }
}

/// One installation-key-encrypted registry. Selection is never authentication.
/// Persistent memory is unavailable throughout this opt-in workspace.
class LocalProfileService extends ChangeNotifier with WidgetsBindingObserver {
  LocalProfileService._({Future<void> Function()? stopSession})
      : _stopSession = stopSession ?? LocalProfileRuntime.stop {
    _owners.add(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
  }

  /// Fixtures must supply an isolated preference/credential store.
  @visibleForTesting
  factory LocalProfileService.forTesting(
          {required Future<void> Function() stopSession}) =>
      LocalProfileService._(stopSession: stopSession);

  static final Set<LocalProfileService> _owners = {};
  static final instance = LocalProfileService._();
  static Future<void> suspendAllForDataWipe() =>
      Future.wait(_owners.toList().map((owner) => owner.suspendForDataWipe()));
  static const modeKey = 'neura.local_profiles.enabled.v1';
  static const storageKey = 'neura.local_profiles.encrypted.v1';
  static const setupPausedMessage =
      'New profile setup is paused to keep your current Neura data accessible.';
  final Future<void> Function() _stopSession;
  final Set<VoidCallback> _sessionRevokers = {};
  List<LocalNeuraProfile> _profiles = const [];
  LocalNeuraProfile? _active;
  bool _enabled = false;
  bool _loaded = false;
  bool _busy = false;
  bool _wiped = false;
  bool _foreground = true;
  bool _observingLifecycle = false;
  void _observeLifecycle() {
    if (_observingLifecycle) return;
    final binding = WidgetsBinding.instance;
    final lifecycle = binding.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    binding.addObserver(this);
    _observingLifecycle = true;
  }

  int _epoch = 0;
  int _storageGeneration = 0;
  Future<void> _tail = Future.value();
  Future<void>? _stopping;
  String? error;

  bool get enabled =>
      _enabled ||
      NeuraPrefsCache.prefsOrNull?.containsKey(modeKey) == true ||
      NeuraPrefsCache.prefsOrNull?.containsKey(storageKey) == true;
  bool get loaded => _loaded;
  bool get busy => _busy;
  int get epoch => _epoch;
  LocalNeuraProfile? get active => _active;
  List<LocalNeuraProfile> get profiles => List.unmodifiable(_profiles);
  bool get canUseSession =>
      enabled &&
      _active != null &&
      !_busy &&
      !_wiped &&
      _foreground &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;
  void addSessionRevoker(VoidCallback revoke) => _sessionRevokers.add(revoke);
  void removeSessionRevoker(VoidCallback revoke) =>
      _sessionRevokers.remove(revoke);

  void _requireGesture(bool directUserGesture) {
    _observeLifecycle();
    if (!directUserGesture ||
        _wiped ||
        !_foreground ||
        SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      throw StateError('Profile operation is unavailable.');
    }
  }

  /// Revocation is synchronous; platform shutdown completes before activation.
  Future<void> lock() {
    _epoch++;
    _active = null;
    for (final revoke in _sessionRevokers.toList()) {
      revoke();
    }
    notifyListeners();
    return _stopping ??= _stopSession().whenComplete(() => _stopping = null);
  }

  Future<bool> _run(Future<void> Function(int generation) body) {
    final generation = _storageGeneration;
    final operation = _tail.then((_) async {
      if (generation != _storageGeneration || _wiped) return false;
      _busy = true;
      error = null;
      notifyListeners();
      try {
        await body(generation);
        return generation == _storageGeneration && !_wiped;
      } catch (_) {
        error =
            'Profile changes could not be confirmed. Retry to reload saved preferences.';
        // A failed/uncertain write must never become an active profile.
        await lock().catchError((_) {});
        return false;
      } finally {
        _busy = false;
        notifyListeners();
      }
    });
    _tail = operation.then((_) {});
    return operation;
  }

  Future<MemoryCrypto> _crypto() async {
    final crypto = await MemoryCrypto.demo();
    crypto.requireOsBackedKey();
    return crypto;
  }

  Future<void> _read() async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.reload();
    _enabled = enabled;
    if (!_enabled) {
      _profiles = const [];
      _loaded = true;
      return;
    }
    final raw = prefs.getString(storageKey);
    if (raw == null) throw StateError('Profile registry is unavailable.');
    final map = await (await _crypto()).decryptJson(raw);
    if (map['version'] != 1 ||
        map['profiles'] is! List ||
        (map['profiles'] as List).length > 8) {
      throw const FormatException('Invalid profile registry.');
    }
    final entries = (map['profiles'] as List)
        .map((p) => LocalNeuraProfile.fromMap(p as Map<String, dynamic>))
        .toList();
    if (entries.map((p) => p.id).toSet().length != entries.length) {
      throw const FormatException('Duplicate profile identifiers.');
    }
    _profiles = List.unmodifiable(entries);
    _loaded = true;
  }

  Future<bool> load() => _run((generation) async {
        if (enabled) _observeLifecycle();
        await lock();
        await _read();
        if (generation != _storageGeneration) _profiles = const [];
      });

  Future<void> _write(List<LocalNeuraProfile> next, int generation) async {
    final prefs = NeuraPrefsCache.prefs;
    final admittedEpoch = _epoch;
    final raw = await (await _crypto()).encryptJson(
        {'version': 1, 'profiles': next.map((p) => p.toMap()).toList()});
    if (generation != _storageGeneration || _wiped || admittedEpoch != _epoch) {
      throw StateError('Profile operation expired.');
    }
    _requireGesture(true);
    final saved = await prefs.setString(storageKey, raw);
    await prefs.reload();
    if (!saved || prefs.getString(storageKey) != raw) {
      throw StateError('Unconfirmed profile save.');
    }
    if (generation != _storageGeneration || _wiped) throw StateError('Wiped.');
    _profiles = List.unmodifiable(next);
    _loaded = true;
  }

  /// New activation is held until an independently reviewed, owner-authorized
  /// return can preserve installation data. A gesture cannot establish who owns
  /// the retained records. Keep this guard at the service boundary as well as
  /// in setup UI; no preference, build flag or testing override lifts the hold.
  ///
  /// Deliberately bypasses [_run]: even its failure cleanup would stop ordinary
  /// sessions. Refusal must not acquire a key, write markers, revoke existing
  /// permissions, or change an already-enabled workspace's session ownership.
  Future<bool> enable({required bool directUserGesture}) {
    error = setupPausedMessage;
    notifyListeners();
    return Future.value(false);
  }

  Future<bool> create(
          {required String label,
          required PersonaProfile persona,
          required NeuraAudience audience,
          required bool directUserGesture}) =>
      _run((generation) async {
        _requireGesture(directUserGesture);
        if (!enabled) throw StateError('Enable profiles first.');
        await _read();
        if (_profiles.length >= 8) throw StateError('Eight profiles maximum.');
        if (_profiles
            .any((p) => p.label.toLowerCase() == label.trim().toLowerCase())) {
          throw StateError('Choose a different profile label.');
        }
        final profile = LocalNeuraProfile.fromMap(LocalNeuraProfile(
                id: const Uuid().v4(),
                label: label.trim(),
                persona: persona,
                audience: audience)
            .toMap());
        await _write([..._profiles, profile], generation);
      });

  Future<bool> select(String id, {required bool directUserGesture}) {
    final requestedEpoch = _epoch;
    return _run((generation) async {
      _requireGesture(directUserGesture);
      if (requestedEpoch != _epoch) throw StateError('Selection expired.');
      final stopped = lock();
      final activationEpoch = _epoch;
      await stopped;
      await _read();
      _requireGesture(directUserGesture);
      if (activationEpoch != _epoch || generation != _storageGeneration) {
        throw StateError('Selection expired.');
      }
      _active = _profiles.singleWhere((p) => p.id == id);
    });
  }

  Future<bool> update(PersonaProfile persona,
          {required String expectedId, required int expectedEpoch}) =>
      _run((generation) async {
        _requireGesture(true);
        if (_active?.id != expectedId || _epoch != expectedEpoch) {
          throw StateError('The profile changed while editing.');
        }
        final old = _active!;
        final next = LocalNeuraProfile.fromMap(LocalNeuraProfile(
                id: old.id,
                label: old.label,
                persona: persona,
                audience: old.audience)
            .toMap());
        await _write(_profiles.map((p) => p.id == next.id ? next : p).toList(),
            generation);
        if (_active?.id == expectedId && _epoch == expectedEpoch) {
          _active = next;
        }
      });

  Future<bool> remove(String id, {required bool directUserGesture}) =>
      _run((generation) async {
        _requireGesture(directUserGesture);
        await lock();
        await _read();
        if (!_profiles.any((p) => p.id == id)) {
          throw StateError('Unknown profile.');
        }
        await _write(_profiles.where((p) => p.id != id).toList(), generation);
      });

  /// Full wipe revokes first, drains all admitted writes, then lets the central
  /// wipe delete preferences and the OS-backed installation key. Never resume.
  Future<void> suspendForDataWipe() async {
    _wiped = true;
    _storageGeneration++;
    // The existing central wipe owns legacy producer shutdown when the
    // workspace was never enabled; do not run those native stops twice.
    Object? stopFailure;
    final stopped =
        (enabled ? lock() : Future<void>.value()).catchError((Object problem) {
      stopFailure = problem;
    });
    await _tail;
    _profiles = const [];
    _loaded = false;
    notifyListeners();
    await stopped;
    if (stopFailure != null) {
      throw StateError('Profile session shutdown was not confirmed.');
    }
  }

  void _onSafety() {
    if (enabled &&
        (SafeBoot.instance.safeMode.value ||
            SafeBoot.instance.restartRequired.value)) {
      unawaited(lock().catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && enabled) unawaited(lock().catchError((_) {}));
  }

  @override
  void dispose() {
    _owners.remove(this);
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    super.dispose();
  }
}
