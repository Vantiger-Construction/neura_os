import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/timeline_vault_io.dart';

import 'helpers/mock_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing tail index recovers the last event sequence', () async {
    final root = await Directory.systemTemp.createTemp(
      'neura-timeline-recovery-',
    );
    addTearDown(() async {
      await TimelineVault.instance.resetAfterDataWipe();
      if (await root.exists()) await root.delete(recursive: true);
    });
    registerMockPathProvider(rootPath: root.path);

    final timeline = Directory(
      '${root.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}timeline',
    );
    await timeline.create(recursive: true);
    final events = File(
      '${timeline.path}${Platform.pathSeparator}events.jsonl',
    );
    await events.writeAsString(
      '${jsonEncode({
        'v': 1,
        'seq': 7,
        'ts': DateTime.utc(2026, 8, 14).toIso8601String(),
        'kind': 'before_crash',
        'source': 'test',
        'data': const <String, Object?>{},
      })}\n',
    );

    await TimelineVault.instance.initialize();
    await TimelineVault.instance.append('after_restart', source: 'test');

    final tail = await TimelineVault.instance.tail(maxLines: 2);
    expect(tail.map((record) => record['seq']), [7, 8]);
  });
}
