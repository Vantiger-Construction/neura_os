import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:neuro_companion/repositories/usage_repository.dart';

class PdfReportService {
  final UsageRepository repository;

  PdfReportService(this.repository);

  Future<String> generateReport() async {
    final entries = repository.getAllEntries();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Neura OS Usage Report',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Generated: ${DateTime.now().toIso8601String()}'),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: ['ID', 'Timestamp', 'Type', 'Source', 'Mood'],
                data: entries
                    .map((e) => [
                          e.id,
                          e.timestamp.toIso8601String(),
                          e.type,
                          e.source,
                          e.moodTag ?? '',
                        ])
                    .toList(),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final fileName =
        'usage_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }
}
