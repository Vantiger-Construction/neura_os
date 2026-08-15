import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/interaction_record.dart';

class InteractionService {
  InteractionService._();

  static final InteractionService instance = InteractionService._();

  static const _storageKey = 'neura_interactions';
  final _uuid = const Uuid();

  List<InteractionRecord> _cache = [];
  bool _loaded = false;
  bool _writesSuspended = false;
  int _dataGeneration = 0;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> _loadIfNeeded(int generation) async {
    if (_loaded || !_isCurrent(generation)) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrent(generation)) return;
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _cache = [];
      _loaded = true;
      return;
    }
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final loaded = list.map(InteractionRecord.fromJson).toList();
    if (!_isCurrent(generation)) return;
    _cache = loaded;
    _loaded = true;
  }

  Future<void> _save(int generation) async {
    _requireCurrent(generation);
    final data = jsonEncode(_cache.map((i) => i.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    _requireCurrent(generation);
    await prefs.setString(_storageKey, data);
    if (!_isCurrent(generation)) {
      await _removeStoredState();
      _requireCurrent(generation);
    }
  }

  Future<void> logInteraction({
    required String profileId,
    required InteractionChannel channel,
    required String contextSnippet,
    required int yourMood,
    required int theirMood,
    required String summary,
    String nextStep = '',
  }) {
    return _enqueueWrite((generation) async {
      await _loadIfNeeded(generation);
      _requireCurrent(generation);
      final record = InteractionRecord(
        id: _uuid.v4(),
        profileId: profileId,
        timestamp: DateTime.now(),
        channel: channel,
        contextSnippet: contextSnippet,
        yourMood: yourMood,
        theirMood: theirMood,
        summary: summary,
        nextStep: nextStep,
      );
      _cache.add(record);
      await _save(generation);
    });
  }

  Future<InteractionRecord?> lastForProfile(String profileId) async {
    if (_writesSuspended) return null;
    final generation = _dataGeneration;
    await _loadIfNeeded(generation);
    if (!_isCurrent(generation)) return null;
    final list = _cache
        .where((i) => i.profileId == profileId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.isEmpty ? null : list.first;
  }

  /// Revokes cached relationship context and prevents it from being restored
  /// by a load/save that was already awaiting platform preferences.
  Future<void> resetAfterDataWipe() async {
    _writesSuspended = true;
    _dataGeneration += 1;
    _cache = [];
    _loaded = false;
    final drain = _writeQueue;
    Object? failure;
    try {
      await drain.timeout(const Duration(seconds: 3));
    } catch (error) {
      failure = error;
      unawaited(
        drain.then<void>(
          (_) => _removeStoredState(),
          onError: (_, __) => _removeStoredState(),
        ).catchError((_) {}),
      );
    }
    try {
      await _removeStoredState();
    } catch (error) {
      failure ??= error;
    }
    _writeQueue = Future<void>.value();
    if (failure != null) {
      throw StateError(
        'Relationship interaction history removal could not be verified.',
      );
    }
  }

  Future<void> _enqueueWrite(
    Future<void> Function(int generation) operation,
  ) {
    if (_writesSuspended) {
      return Future<void>.error(
        StateError('Relationship interaction writes are suspended.'),
      );
    }
    final generation = _dataGeneration;
    Future<void> run() {
      _requireCurrent(generation);
      return operation(generation);
    }

    final next = _writeQueue.then<void>(
      (_) => run(),
      onError: (_) => run(),
    );
    _writeQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  bool _isCurrent(int generation) =>
      !_writesSuspended && generation == _dataGeneration;

  void _requireCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('Relationship interaction operation was invalidated.');
    }
  }

  static Future<void> _removeStoredState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    if (prefs.containsKey(_storageKey)) {
      throw StateError('Relationship interaction deletion was not verified.');
    }
  }
}
