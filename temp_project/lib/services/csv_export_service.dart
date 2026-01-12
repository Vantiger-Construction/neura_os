import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:neura_os/models/usage_entry.dart';
import 'package:neura_os/repositories/usage_repository.dart';

class CsvExportService {
  final UsageRepository repository;

  CsvExportService(this.repository);

  Future<String> exportAllEntries() async {
    final entries = await repository.getAllEntries();
    final directory = await getTemporaryDirectory();
    final fileName = 'usage_entries_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${directory.path}/$fileName');

    final buffer = StringBuffer();
    buffer.writeln('ID,Timestamp,Type,Source,MoodTag');

    for (final entry in entries) {
      buffer.writeln('${entry.id},${entry.timestamp.toIso8601String()},${entry.type},${entry.source},${entry.moodTag}');
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }
}