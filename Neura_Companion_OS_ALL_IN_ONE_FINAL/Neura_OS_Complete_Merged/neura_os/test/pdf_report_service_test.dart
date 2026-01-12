import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neura_companion/models/usage_entry.dart';
import 'package:neura_companion/services/pdf_report_service.dart';
import 'package:neura_companion/repositories/usage_repository.dart';

class FakeRepo implements UsageRepository {
  @override
  Future<List<UsageEntry>> getAllEntries() async {
    return [
      UsageEntry(
        id: 'a',
        timestamp: DateTime.utc(2025, 1, 1),
        type: 't1',
        source: 's1',
        moodTag: 'm1',
      ),
    ];
  }
  @override
  Future<void> saveEntry(UsageEntry entry) => throw UnimplementedError();
}

void main() {
  test('generateReport produces a PDF file', () async {
    final repo = FakeRepo();
    final service = PdfReportService(repo);
    final path = await service.generateReport();
    final file = File(path);
    expect(await file.exists(), isTrue);
    final header = (await file.readAsBytes()).sublist(0, 4);
    expect(String.fromCharCodes(header), '%PDF');
    await file.delete();
  });
}
