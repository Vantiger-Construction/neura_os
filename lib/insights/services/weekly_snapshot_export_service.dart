import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/weekly_snapshot_entry.dart';
import 'weekly_snapshot_service.dart';

/// Exports Weekly Life Snapshot data (mood, rituals, storms, care mode use)
/// to CSV/PDF so it can be shared, e.g. with a therapist or support person.
class WeeklySnapshotExportService {
  WeeklySnapshotExportService._internal();
  static final WeeklySnapshotExportService instance =
      WeeklySnapshotExportService._internal();

  final _service = WeeklySnapshotService.instance;

  String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<WeeklySnapshotEntry>> _entriesFor(int days) =>
      _service.lastNDays(days);

  /// Writes a CSV of the last [days] days of snapshots and returns its path.
  Future<String> exportCsv({int days = 30}) async {
    final entries = await _entriesFor(days);
    final buffer = StringBuffer();
    buffer.writeln('Date,MoodScore,StormsCount,RitualsCompleted,UsedCareMode,Note');
    for (final e in entries) {
      final note = e.note.replaceAll(',', ';').replaceAll('\n', ' ');
      buffer.writeln(
        '${_dateLabel(e.date)},${e.moodScore.toStringAsFixed(1)},${e.stormsCount},${e.ritualsCompleted},${e.usedCareMode},$note',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/neura_weekly_snapshot_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  /// Builds a PDF summary of the last [days] days of snapshots and returns its path.
  Future<String> exportPdf({int days = 30}) async {
    final entries = await _entriesFor(days);
    final summary = await _service.buildWeeklySummaryText();

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
          pw.Text(summary, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 16),
          if (entries.isEmpty)
            pw.Text('No check-ins logged for this range.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Mood', 'Storms', 'Rituals', 'Care'],
              data: [
                for (final e in entries)
                  [
                    _dateLabel(e.date),
                    e.moodScore.toStringAsFixed(1),
                    '${e.stormsCount}',
                    '${e.ritualsCompleted}',
                    e.usedCareMode ? 'yes' : 'no',
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
