import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:neura_companion/data/hive_adapters.dart';
import 'package:neura_companion/data/local_usage_repository.dart';
import 'package:neura_companion/models/usage_entry.dart';

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('hive_test');
    Hive.init(dir.path);
    Hive.registerAdapter(HiveUsageEntryAdapter());
    Hive.registerAdapter(HiveRitualAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('saveEntry and getAllEntries roundtrip', () async {
    final repo = LocalUsageRepository();
    final now = DateTime.now();
    final entry = UsageEntry(
      id: 'test1',
      timestamp: now,
      type: 'meditation',
      source: 'manual',
      moodTag: 'calm',
    );
    await repo.saveEntry(entry);
    final result = await repo.getAllEntries();
    expect(result.length, greaterThanOrEqualTo(1));
    final fetched = result.firstWhere((e) => e.id == 'test1');
    expect(fetched.timestamp, equals(now));
    expect(fetched.type, 'meditation');
    expect(fetched.source, 'manual');
    expect(fetched.moodTag, 'calm');
  });
}
