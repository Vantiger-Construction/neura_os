
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/neura_promise.dart';

class PromiseService {
  PromiseService._();

  static final PromiseService instance = PromiseService._();

  static const _storageKey = 'neura_promises';
  final _uuid = const Uuid();

  List<NeuraPromise> _cache = [];

  Future<void> _loadIfNeeded() async {
    if (_cache.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _cache = [];
      return;
    }
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
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
    return _cache
        .where((p) => p.status == PromiseStatus.pending)
        .toList()
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
    return promise;
  }

  Future<void> updateStatus(String id, PromiseStatus status) async {
    await _loadIfNeeded();
    final idx = _cache.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    _cache[idx] = _cache[idx].copyWith(status: status);
    await _save();
  }

  Future<int> openCount() async {
    await _loadIfNeeded();
    return _cache.where((p) => p.status == PromiseStatus.pending).length;
  }
}
