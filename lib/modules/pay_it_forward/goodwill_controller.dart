import 'package:flutter/foundation.dart';

import 'goodwill_models.dart';
import 'goodwill_store.dart';

class GoodwillController {
  GoodwillController._();
  static final GoodwillController instance = GoodwillController._();

  final ValueNotifier<List<KindnessAct>> acts = ValueNotifier<List<KindnessAct>>(<KindnessAct>[]);
  final ValueNotifier<int> streak = ValueNotifier<int>(0);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final loadedActs = await GoodwillStore.instance.getAll();
    acts.value = loadedActs;
    streak.value = _calculateStreakEndingOn(_latestActDate(loadedActs));
    _loaded = true;
  }

  DateTime? _latestActDate(List<KindnessAct> list) {
    if (list.isEmpty) return null;
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list.last.timestamp;
  }

  /// Adds an act and returns whether the streak increased.
  Future<bool> addAct(KindnessAct act) async {
    await ensureLoaded();

    final before = streak.value;

    final list = List<KindnessAct>.from(acts.value)..add(act);
    // Bound size to keep prefs safe.
    if (list.length > 2000) {
      list.removeRange(0, list.length - 2000);
    }

    await GoodwillStore.instance.setAll(list);
    acts.value = list;

    // Streak is computed ending on the act's date.
    final after = _calculateStreakEndingOn(act.timestamp, list: list);
    streak.value = after;
    return after > before;
  }

  Future<void> deleteAct(KindnessAct act) async {
    await ensureLoaded();
    final list = List<KindnessAct>.from(acts.value)
      ..removeWhere((x) => x.timestamp == act.timestamp && x.category == act.category && x.note == act.note);
    await GoodwillStore.instance.setAll(list);
    acts.value = list;
    streak.value = _calculateStreakEndingOn(_latestActDate(list), list: list);
  }

  Future<void> wipeAll() async {
    await GoodwillStore.instance.wipe();
    acts.value = <KindnessAct>[];
    streak.value = 0;
  }

  void resetAfterDataWipe() {
    acts.value = const <KindnessAct>[];
    streak.value = 0;
    _loaded = false;
  }

  int _calculateStreakEndingOn(DateTime? end, {List<KindnessAct>? list}) {
    final items = list ?? acts.value;
    if (end == null || items.isEmpty) return 0;

    final days = <String>{};
    for (final a in items) {
      final d = DateTime(a.timestamp.year, a.timestamp.month, a.timestamp.day);
      days.add(_dayKey(d));
    }

    var streakCount = 0;
    var cursor = DateTime(end.year, end.month, end.day);
    while (days.contains(_dayKey(cursor))) {
      streakCount++;
      cursor = cursor.subtract(const Duration(days: 1));
      // sanity cap
      if (streakCount > 3650) break;
    }

    return streakCount;
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
