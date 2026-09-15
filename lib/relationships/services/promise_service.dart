import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../notifications/neura_notifications_prefs.dart';
import '../../notifications/neura_notifications_service.dart';
import '../models/neura_promise.dart';

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

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_cache.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<List<NeuraPromise>> all() async {
    await _loadIfNeeded();
    return List.unmodifiable(_cache);
  }

  Future<List<NeuraPromise>> openPromises() async {
    await _loadIfNeeded();
    return _cache.where((p) => p.status == PromiseStatus.pending).toList()
      ..sort((a, b) {
        final ad = a.dueAt ?? DateTime.now().add(const Duration(days: 365));
        final bd = b.dueAt ?? DateTime.now().add(const Duration(days: 365));
        return ad.compareTo(bd);
      });
  }

  Future<List<NeuraPromise>> forProfile(String profileId) async {
    await _loadIfNeeded();
    return _cache.where((p) => p.profileId == profileId).toList();
  }

  Future<NeuraPromise> create({
    String? profileId,
    required String description,
    DateTime? dueAt,
  }) async {
    await _loadIfNeeded();
    final now = DateTime.now();
    final promise = NeuraPromise(
      id: _uuid.v4(),
      description: description,
      profileId: profileId,
      createdAt: now,
      dueAt: dueAt,
    );
    _cache.add(promise);
    await _save();
    await _syncReminder(promise);
    return promise;
  }

  /// Edits an existing promise's description and/or due date. Pass
  /// [clearDueAt] to remove a due date entirely (a null [dueAt] otherwise
  /// leaves the existing due date untouched, matching [NeuraPromise.copyWith]
  /// semantics elsewhere in this service).
  Future<NeuraPromise?> update(
    String id, {
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
  }) async {
    await _loadIfNeeded();
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
    await _save();
    await _syncReminder(updated);
    return updated;
  }

  Future<void> updateStatus(String id, PromiseStatus status) async {
    await _loadIfNeeded();
    final idx = _cache.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final updated = _cache[idx].copyWith(status: status);
    _cache[idx] = updated;
    await _save();
    await _syncReminder(updated);
  }

  /// Re-applies the current reminders-enabled preference to every promise.
  /// Call this after the promise-reminders toggle changes, so existing
  /// scheduled reminders are cancelled (or (re)scheduled) to match.
  Future<void> syncAllReminders() async {
    await _loadIfNeeded();
    for (final promise in _cache) {
      if (promise.dueAt != null) {
        await _syncReminder(promise);
      }
    }
  }

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

  Future<int> openCount() async {
    await _loadIfNeeded();
    return _cache.where((p) => p.status == PromiseStatus.pending).length;
  }

  void resetAfterDataWipe() {
    _cache = [];
  }
}
