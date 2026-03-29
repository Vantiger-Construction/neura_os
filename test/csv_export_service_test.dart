import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/models/usage_entry.dart';
import 'package:neuro_companion/services/csv_export_service.dart';
import 'package:neuro_companion/repositories/usage_repository.dart';

class FakeRepo extends UsageRepository {
  FakeRepo() : super() {
    addEntry(
      UsageEntry(
        id: '1',
        timestamp: DateTime.utc(2025, 1, 1, 12, 0),
        type: 'test',
        source: 'unit-test',
        moodTag: 'happy',
      ),
    );
    addEntry(
      UsageEntry(
        id: '2',
        timestamp: DateTime.utc(2025, 1, 2, 13, 30),
        type: 'test2',
        source: 'unit-test',
        moodTag: 'sad',
      ),
    );
  }
}

void main() {
  test('exportAllEntries creates a CSV file', () async {
    final repo = FakeRepo();
    final service = CsvExportService(repo);
    final path = await service.exportAllEntries();
    final file = File(path);
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines.length, 3);
    expect(lines[0], 'ID,Timestamp,Type,Source,MoodTag');
    await file.delete();
  });
}
