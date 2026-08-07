import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'neura_recap_service.dart';

/// PDF export for [RecapData] -- same pattern as
/// [WeeklySnapshotExportService] (pdf + printing package family,
/// share_plus for handoff). No new dependencies.
class NeuraRecapExportService {
  NeuraRecapExportService._();
  static final NeuraRecapExportService instance = NeuraRecapExportService._();

  String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<String> exportPdf(RecapData data) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (ctx) => [
          pw.Text('Neura Recap',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('${_dateLabel(data.from)} – ${_dateLabel(data.to)}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 20),
          if (data.moodAvg != null)
            pw.Text(
              'Mood: avg ${data.moodAvg}/10 (range ${data.moodMin}–${data.moodMax}) '
              'across ${data.moodEntries.length} check-in(s)',
              style: const pw.TextStyle(fontSize: 13),
            )
          else
            pw.Text('No mood check-ins logged for this range.',
                style: const pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 8),
          pw.Text('Kindness acts: ${data.kindnessActsTotal}', style: const pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 4),
          pw.Text('Quests completed: ${data.questsDoneTotal}', style: const pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Joy Moments: ${data.joyMomentsCompleted} enjoyed'
            '${data.joyMomentsSkipped > 0 ? ', ${data.joyMomentsSkipped} skipped' : ''}',
            style: const pw.TextStyle(fontSize: 13),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'This is a personal recap, not a medical or diagnostic summary.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/neura_recap_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  Future<void> share(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'My Neura Recap');
  }
}
