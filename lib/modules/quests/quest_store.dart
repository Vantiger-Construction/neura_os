import 'dart:math';
import 'quest_models.dart';
import '../../startup/neura_prefs_cache.dart';

class QuestStore {
  QuestStore._();
  static final QuestStore instance = QuestStore._();

  static const _questsKey = 'neura.quests.v1';
  static const _doneKey = 'neura.quests.done.v1';

  String _id() {
    final r = Random();
    return 'q_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 32)}';
  }

  Future<List<Quest>> getQuests() async {
    final sp = NeuraPrefsCache.prefs;
    return decodeQuestList(sp.getString(_questsKey) ?? '');
  }

  Future<List<QuestDone>> getDone() async {
    final sp = NeuraPrefsCache.prefs;
    return decodeDoneList(sp.getString(_doneKey) ?? '');
  }

  Future<void> _writeQuests(List<Quest> list) async {
    final sp = NeuraPrefsCache.prefs;
    await sp.setString(_questsKey, encodeQuestList(list));
  }

  Future<void> _writeDone(List<QuestDone> list) async {
    final sp = NeuraPrefsCache.prefs;
    await sp.setString(_doneKey, encodeDoneList(list));
  }

  Future<Quest> addQuest({required String title, String details = ''}) async {
    final list = await getQuests();
    final q = Quest(
        id: _id(),
        title: title.trim(),
        details: details.trim(),
        createdAt: DateTime.now());
    list.add(q);
    await _writeQuests(list);
    return q;
  }

  Future<void> add(Quest quest) async {
    final list = await getQuests();
    list.add(quest);
    await _writeQuests(list);
  }

  Future<void> toggleArchived(String questId) async {
    final list = await getQuests();
    final idx = list.indexWhere((q) => q.id == questId);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(archived: !list[idx].archived);
    await _writeQuests(list);
  }

  Future<void> deleteQuest(String questId) async {
    final list = await getQuests();
    list.removeWhere((q) => q.id == questId);
    await _writeQuests(list);

    final done = await getDone();
    done.removeWhere((d) => d.questId == questId);
    await _writeDone(done);
  }

  Future<void> markDoneToday(String questId) async {
    final done = await getDone();
    final today = normalizeDay(DateTime.now());
    if (done.any((d) => d.questId == questId && normalizeDay(d.day) == today)) {
      return;
    }
    done.add(QuestDone(questId: questId, day: today));
    // keep bounded
    if (done.length > 5000) {
      done.removeRange(0, done.length - 5000);
    }
    await _writeDone(done);
  }

  Future<void> unmarkDoneToday(String questId) async {
    final done = await getDone();
    final today = normalizeDay(DateTime.now());
    done.removeWhere(
        (d) => d.questId == questId && normalizeDay(d.day) == today);
    await _writeDone(done);
  }

  Future<int> currentStreak() async {
    final done = await getDone();
    if (done.isEmpty) return 0;
    final days = done.map((e) => normalizeDay(e.day)).toSet().toList()..sort();
    if (days.isEmpty) return 0;

    final today = normalizeDay(DateTime.now());
    // streak counts up to today if today has completion; else up to yesterday
    DateTime cursor =
        days.contains(today) ? today : today.subtract(const Duration(days: 1));

    int streak = 0;
    while (days.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<int> doneCountLastDays(int daysBack) async {
    final done = await getDone();
    final cutoff = DateTime.now().subtract(Duration(days: daysBack));
    return done.where((d) => d.day.isAfter(cutoff)).length;
  }

  Future<void> wipe() async {
    final sp = NeuraPrefsCache.prefs;
    await sp.remove(_questsKey);
    await sp.remove(_doneKey);
  }
}
