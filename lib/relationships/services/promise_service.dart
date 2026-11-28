import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../profiles/local_profile_service.dart';
import '../../notifications/neura_notifications_prefs.dart';
import '../../notifications/neura_notifications_service.dart';
import '../models/neura_promise.dart';
import 'promise_garden.dart';

abstract interface class PromiseReminderScheduler {
  Future<void> schedulePromiseReminder({
    required String promiseId,
    required String description,
    required DateTime dueAt,
  });
  Future<void> cancelPromiseReminder(String promiseId);
}

class _NeuraNotificationsPromiseReminderScheduler
    implements PromiseReminderScheduler {
  const _NeuraNotificationsPromiseReminderScheduler();

  @override
  Future<void> schedulePromiseReminder({
    required String promiseId,
    required String description,
    required DateTime dueAt,
  }) =>
      NeuraNotificationsService.instance.schedulePromiseReminder(
        promiseId: promiseId,
        description: description,
        dueAt: dueAt,
      );

  @override
  Future<void> cancelPromiseReminder(String promiseId) =>
      NeuraNotificationsService.instance.cancelPromiseReminder(promiseId);
}

class PromiseService {
  PromiseService._({
    PromiseReminderScheduler? scheduler,
    bool Function()? remindersEnabled,
  })  : _scheduler =
            scheduler ?? const _NeuraNotificationsPromiseReminderScheduler(),
        _remindersEnabled = remindersEnabled ??
            (() => NeuraNotificationsPrefsController
                .instance.prefs.value.promiseReminderEnabled);

  static final PromiseService instance = PromiseService._();

  @visibleForTesting
  factory PromiseService.forTesting({
    required PromiseReminderScheduler scheduler,
    bool Function()? remindersEnabled,
  }) {
    return PromiseService._(
      scheduler: scheduler,
      remindersEnabled: remindersEnabled ?? () => true,
    );
  }

  static const _storageKey = 'neura_promises';
  final _uuid = const Uuid();
  final PromiseReminderScheduler _scheduler;
  final bool Function() _remindersEnabled;

  List<NeuraPromise> _cache = [];
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _suspended = false;

  void suspendForDataWipe() {
    _suspended = true;
    _generation++;
  }

  void invalidateSession() => _generation++;
  Future<void> drainForDataWipe() => _tail.timeout(const Duration(seconds: 30));

  @visibleForTesting
  static void resetWipeGateForTesting() {
    instance._suspended = false;
    instance._generation++;
    instance._cache = [];
  }

  Future<T> _run<T>(Future<T> Function(void Function()) operation,
      {bool Function()? stillAllowed}) {
    final generation = _generation;
    final epoch = LocalProfileService.instance.epoch;
    void requireCurrent() {
      if (_suspended ||
          generation != _generation ||
          epoch != LocalProfileService.instance.epoch ||
          LocalProfileService.instance.enabled ||
          stillAllowed?.call() == false) {
        throw StateError('This promise request is no longer available.');
      }
    }

    try {
      requireCurrent();
    } catch (e, st) {
      return Future.error(e, st);
    }
    final next = _tail.then((_) async {
      requireCurrent();
      try {
        final result = await operation(requireCurrent);
        requireCurrent();
        return result;
      } catch (_) {
        _cache = [];
        rethrow;
      }
    });
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _loadIfNeeded() async {
    if (_cache.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _cache = [];
      return;
    }
    final list =
        (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    _cache = list.map(NeuraPromise.fromJson).toList();
  }

  Future<void> _save(void Function() requireCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    requireCurrent();
    final data = jsonEncode(_cache.map((p) => p.toJson()).toList());
    final saved = await prefs.setString(_storageKey, data);
    requireCurrent();
    if (!saved) {
      await prefs.reload();
      throw StateError('The promise could not be saved on this device.');
    }
  }

  Future<List<NeuraPromise>> all() => _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        return List.unmodifiable(_cache);
      });

  Future<List<NeuraPromise>> openPromises() => _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        return _cache.where((p) => p.status == PromiseStatus.pending).toList()
          ..sort((a, b) {
            final ad = a.dueAt ?? DateTime.now().add(const Duration(days: 365));
            final bd = b.dueAt ?? DateTime.now().add(const Duration(days: 365));
            return ad.compareTo(bd);
          });
      });

  Future<List<NeuraPromise>> forProfile(String profileId) =>
      _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        return _cache.where((p) => p.profileId == profileId).toList();
      });

  Future<NeuraPromise> create({
    String? profileId,
    required String description,
    DateTime? dueAt,
    bool Function()? stillAllowed,
  }) =>
      _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        final now = DateTime.now();
        final promise = NeuraPromise(
          id: _uuid.v4(),
          description: description,
          profileId: profileId,
          createdAt: now,
          dueAt: dueAt,
        );
        _cache.add(promise);
        await _save(requireCurrent);
        requireCurrent();
        await _syncReminder(promise);
        return promise;
      }, stillAllowed: stillAllowed);

  /// Edits an existing promise's description and/or due date. Pass
  /// [clearDueAt] to remove a due date entirely (a null [dueAt] otherwise
  /// leaves the existing due date untouched, matching [NeuraPromise.copyWith]
  /// semantics elsewhere in this service).
  Future<NeuraPromise?> update(
    String id, {
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
  }) =>
      _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        final idx = _cache.indexWhere((p) => p.id == id);
        if (idx == -1) return null;
        final current = _cache[idx];
        final updated = NeuraPromise(
          id: current.id,
          profileId: current.profileId,
          description: description ?? current.description,
          createdAt: current.createdAt,
          dueAt: clearDueAt ? null : (dueAt ?? current.dueAt),
          status: current.status,
        );
        _cache[idx] = updated;
        await _save(requireCurrent);
        requireCurrent();
        await _syncReminder(updated);
        return updated;
      });

  Future<void> updateStatus(String id, PromiseStatus status) =>
      _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        final idx = _cache.indexWhere((p) => p.id == id);
        if (idx == -1) return;
        final updated = _cache[idx].copyWith(status: status);
        _cache[idx] = updated;
        await _save(requireCurrent);
        requireCurrent();
        await _syncReminder(updated);
        // A kept promise grows the plant in Neura's penthouse.
        if (identical(this, instance)) {
          unawaited(PromiseGardenService.instance.refresh());
        }
      });

  /// Re-applies the current reminders-enabled preference to every promise.
  /// Call this after the promise-reminders toggle changes, so existing
  /// scheduled reminders are cancelled (or (re)scheduled) to match.
  Future<void> syncAllReminders() => _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        for (final promise in _cache) {
          if (promise.dueAt != null) {
            requireCurrent();
            await _syncReminder(promise);
          }
        }
      });

  Future<void> _syncReminder(NeuraPromise promise) async {
    final active = promise.status == PromiseStatus.pending &&
        promise.dueAt != null &&
        _remindersEnabled();
    if (!active) {
      await _scheduler.cancelPromiseReminder(promise.id);
      return;
    }
    await _scheduler.schedulePromiseReminder(
      promiseId: promise.id,
      description: promise.description,
      dueAt: promise.dueAt!,
    );
  }

  Future<int> openCount() => _run((requireCurrent) async {
        await _loadIfNeeded();
        requireCurrent();
        return _cache.where((p) => p.status == PromiseStatus.pending).length;
      });

  void resetAfterDataWipe() {
    _cache = [];
  }
}
