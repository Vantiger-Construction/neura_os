import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../modules/review/weekly_review_store.dart';
import '../../weekly/services/weekly_snapshot_service.dart';

/// Exports the consolidated Weekly Life Snapshot (mood entries, storms/dreams
/// vibe, kindness + quest numbers) to CSV/PDF so it can be shared, e.g. with
/// a therapist or support person.
class WeeklySnapshotExportService {
  WeeklySnapshotExportService._internal();
  static final WeeklySnapshotExportService instance =
      WeeklySnapshotExportService._internal();

  String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _timeLabel(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<List<MoodEntry>> _moodEntriesFor(int days) async {
    final all = await MoodStore.instance.getAll();
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));
    return all.where((m) => !m.timestamp.isBefore(cutoff)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Writes a CSV of the last [days] days of mood check-ins and returns its path.
  Future<String> exportCsv({int days = 30}) async {
    final entries = await _moodEntriesFor(days);
    final buffer = StringBuffer();
    buffer.writeln('Date,Time,Mood,Note');
    for (final e in entries) {
      final note = e.note.replaceAll(',', ';').replaceAll('\n', ' ');
      buffer.writeln(
        '${_dateLabel(e.timestamp)},${_timeLabel(e.timestamp)},${e.mood0to10},$note',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/neura_weekly_snapshot_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Builds a PDF summary of the last [days] days and returns its path.
  /// Combines mood check-ins, the storms/dreams vibe summary, and the
  /// weekly review numbers (kindness acts, quests done, top learned).
  Future<String> exportPdf({int days = 30}) async {
    final entries = await _moodEntriesFor(days);
    final summary = await WeeklySnapshotService.instance.buildSummary(days: days);
    final review = await WeeklyReviewStore.instance.generate();

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (ctx) => [
          pw.Text('Neura Weekly Life Snapshot',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Range: last $days day(s) · Generated ${_dateLabel(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.Text(summary.vibeSentence, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 8),
          pw.Text(
            'Storms: ${summary.stormsCount} (safety alerts: ${summary.safetyStormsCount}) · '
            'Dreams: ${summary.dreamsCount}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Mood: avg ${review.moodAvg}/10 (min ${review.moodMin}, max ${review.moodMax}) '
            'across ${review.moodSamples} check-in(s) · '
            'Kindness acts: ${review.kindnessActs} · Quests done: ${review.questDone}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          if (entries.isEmpty)
            pw.Text('No mood check-ins logged for this range.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Time', 'Mood', 'Note'],
              data: [
                for (final e in entries)
                  [
                    _dateLabel(e.timestamp),
                    _timeLabel(e.timestamp),
                    '${e.mood0to10}',
                    e.note,
                  ],
              ],
            ),
          pw.SizedBox(height: 18),
          pw.Text(
            'This summary is reflective, not diagnostic. If you feel unsafe '
            'or in crisis, please reach out to a mental health professional '
            'or local emergency services.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/neura_weekly_snapshot_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  Future<void> shareFiles(List<String> paths, {String? text}) async {
    if (paths.isEmpty) return;
    await Share.shareXFiles(
      [for (final p in paths) XFile(p)],
      text: text ?? 'Neura Weekly Life Snapshot',
    );
  }
}
