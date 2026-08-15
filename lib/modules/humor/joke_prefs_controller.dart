import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../../startup/neura_prefs_cache.dart';

/// Persisted favorites/dislikes/spicy-toggle for [NeuraJokeEngine].
class JokePrefsController {
  JokePrefsController._();
  static final JokePrefsController instance = JokePrefsController._();

  static const _kFavoritesKey = 'neura.jokes.favorites.v1';
  static const _kDislikesKey = 'neura.jokes.dislikes.v1';
  static const _kSpicyKey = 'neura.jokes.includeSpicy.v1';

  final ValueNotifier<List<String>> favorites = ValueNotifier<List<String>>(const []);
  final ValueNotifier<List<String>> dislikes = ValueNotifier<List<String>>(const []);
  final ValueNotifier<bool> includeSpicy = ValueNotifier<bool>(false);

  Future<void> init() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      favorites.value = sp.getStringList(_kFavoritesKey) ?? const [];
      dislikes.value = sp.getStringList(_kDislikesKey) ?? const [];
      includeSpicy.value = sp.getBool(_kSpicyKey) ?? false;
    } catch (e) {
      await AppLog.instance.warn('JokePrefsController.init failed: $e');
    }
  }

  Future<void> toggleFavorite(String joke) async {
    final next = List<String>.from(favorites.value);
    if (next.contains(joke)) {
      next.remove(joke);
    } else {
      next.add(joke);
    }
    favorites.value = next;
    await _persistList(_kFavoritesKey, next);
  }

  Future<void> addDislike(String joke) async {
    if (dislikes.value.contains(joke)) return;
    final next = List<String>.from(dislikes.value)..add(joke);
    dislikes.value = next;
    await _persistList(_kDislikesKey, next);
  }

  Future<void> setIncludeSpicy(bool value) async {
    includeSpicy.value = value;
    try {
      await NeuraPrefsCache.prefs.setBool(_kSpicyKey, value);
    } catch (e) {
      await AppLog.instance.warn('JokePrefsController.setIncludeSpicy failed: $e');
    }
  }

  bool isFavorite(String joke) => favorites.value.contains(joke);

  Future<void> _persistList(String key, List<String> value) async {
    try {
      await NeuraPrefsCache.prefs.setStringList(key, value);
    } catch (e) {
      await AppLog.instance.warn('JokePrefsController persist($key) failed: $e');
    }
  }

  void resetAfterDataWipe() {
    favorites.value = const <String>[];
    dislikes.value = const <String>[];
    includeSpicy.value = false;
  }
}
