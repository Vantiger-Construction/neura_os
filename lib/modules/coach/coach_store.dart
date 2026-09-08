import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/app_log.dart';
import 'coach_models.dart';
import '../../startup/neura_prefs_cache.dart';

class CoachStore {
  CoachStore._();
  static final CoachStore instance = CoachStore._();

  static const _keyTimeline = 'neura.coach.timeline.v1';

  final ValueNotifier<List<CoachNote>> notes = ValueNotifier(<CoachNote>[]);

  Future<void> init() async {
    notes.value = await getAll();
  }

  String _id() {
    final r = Random();
    return 'c_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 32)}';
  }

  Future<List<CoachNote>> getAll() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      final raw = sp.getString(_keyTimeline);
      if (raw == null || raw.trim().isEmpty) return <CoachNote>[];
      return decodeCoachNotes(raw);
    } catch (e, st) {
      await AppLog.instance.caught('coach_store_read_failed', e, st);
      return <CoachNote>[];
    }
  }

  Future<void> _write(List<CoachNote> notes) async {
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.setString(_keyTimeline, encodeCoachNotes(notes));
    } catch (e, st) {
      await AppLog.instance.caught('coach_store_write_failed', e, st);
    }
  }

  Future<CoachNote> add({
    required CoachSourceType source,
    required String title,
    required String body,
    List<String> tags = const [],
  }) async {
    final all = await getAll();
    final note = CoachNote(
      id: _id(),
      createdAt: DateTime.now(),
      source: source,
      title: title.trim(),
      body: body.trim(),
      tags: tags
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
    );
    all.add(note);
    // Cap so storage doesn't balloon forever.
    const cap = 500;
    if (all.length > cap) {
      all.removeRange(0, all.length - cap);
    }
    await _write(all);
    notes.value = List.from(all); // Update the notifier
    return note;
  }


  Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((n) => n.id == id);
    await _write(all);
    notes.value = List.from(all); // Update the notifier
  }

  Future<void> clear() async {
    try {
      final sp = NeuraPrefsCache.prefs;
      await sp.remove(_keyTimeline);
    } catch (e, st) {
      await AppLog.instance.caught('coach_store_clear_failed', e, st);
    }
  }

  void resetAfterDataWipe() {
    notes.value = const <CoachNote>[];
  }
}
