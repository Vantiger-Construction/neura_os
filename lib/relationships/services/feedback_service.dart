
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SuggestionFeedback {
  final String suggestionType;
  final int rating; // -1, 0, +1

  SuggestionFeedback({
    required this.suggestionType,
    required this.rating,
  });

  Map<String, dynamic> toJson() => {
        'suggestionType': suggestionType,
        'rating': rating,
      };

  factory SuggestionFeedback.fromJson(Map<String, dynamic> json) {
    return SuggestionFeedback(
      suggestionType: json['suggestionType'] as String,
      rating: (json['rating'] as num).toInt(),
    );
  }
}

class FeedbackService {
  FeedbackService._();

  static final FeedbackService instance = FeedbackService._();

  static const _storageKey = 'neura_suggestion_feedback';

  List<SuggestionFeedback> _cache = [];
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
    final loaded = list.map(SuggestionFeedback.fromJson).toList();
    if (!_isCurrent(generation)) return;
    _cache = loaded;
    _loaded = true;
  }

  Future<void> _save(int generation) async {
    _requireCurrent(generation);
    final data = jsonEncode(_cache.map((f) => f.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    _requireCurrent(generation);
    await prefs.setString(_storageKey, data);
    if (!_isCurrent(generation)) {
      await _removeStoredState();
      _requireCurrent(generation);
    }
  }

  Future<void> addFeedback(String suggestionType, int rating) {
    return _enqueueWrite((generation) async {
      await _loadIfNeeded(generation);
      _requireCurrent(generation);
      _cache.add(SuggestionFeedback(
        suggestionType: suggestionType,
        rating: rating,
      ));
      await _save(generation);
    });
  }

  Future<double> preferenceScore(String suggestionType) async {
    if (_writesSuspended) return 0;
    final generation = _dataGeneration;
    await _loadIfNeeded(generation);
    if (!_isCurrent(generation)) return 0;
    final list =
        _cache.where((f) => f.suggestionType == suggestionType).toList();
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (acc, f) => acc + f.rating);
    return sum / (list.length * 1.0);
  }

  /// Revokes cached suggestion feedback and prevents a pending save from
  /// recreating its preference record after a full local-data wipe.
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
        'Relationship feedback removal could not be verified.',
      );
    }
  }

  Future<void> _enqueueWrite(
    Future<void> Function(int generation) operation,
  ) {
    if (_writesSuspended) {
      return Future<void>.error(
        StateError('Relationship feedback writes are suspended.'),
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
      throw StateError('Relationship feedback operation was invalidated.');
    }
  }

  static Future<void> _removeStoredState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    if (prefs.containsKey(_storageKey)) {
      throw StateError('Relationship feedback deletion was not verified.');
    }
  }
}
