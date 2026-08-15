import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/core/app_log_record.dart';

void main() {
  group('AppLogRecordFactory', () {
    test('creates versioned, ordered records for one launch session', () {
      final factory = AppLogRecordFactory(
        platform: 'windows',
        sessionStartedAt: DateTime.utc(2026, 8, 15),
      );

      final first = factory.build(
        level: 'info',
        event: 'boot_started',
        data: const <String, Object?>{},
        at: DateTime.utc(2026, 8, 15, 1),
      );
      final second = factory.build(
        level: 'error',
        event: 'boot_failed',
        data: const <String, Object?>{'fatal': true},
        at: DateTime.utc(2026, 8, 15, 1, 0, 1),
      );

      expect(first['v'], AppLogRecordFactory.schemaVersion);
      expect(first['platform'], 'windows');
      expect(first['session'], second['session']);
      expect(first['seq'], 1);
      expect(second['seq'], 2);
      expect(second['data'], const <String, Object?>{'fatal': true});
      expect(() => jsonEncode(second), returnsNormally);
    });
  });

  group('AppLogSanitizer', () {
    test('removes credentials and user-authored content recursively', () {
      final sanitized = AppLogSanitizer.map(<String, Object?>{
        'apiKey': 'sk-ant-abcdefghijklmnop',
        'authorization': 'Bearer top.secret.token',
        'displayText': 'private chat turn',
        'has_image': true,
        'nested': <String, Object?>{
          'journal_note': 'private journal entry',
          'status': 'request failed for person@example.com',
        },
      });

      expect(sanitized['apiKey'], '[REDACTED]');
      expect(sanitized['authorization'], '[REDACTED]');
      expect(sanitized['displayText'], '[CONTENT_REDACTED]');
      expect(sanitized['has_image'], isTrue);
      expect(
        (sanitized['nested'] as Map<String, Object?>)['journal_note'],
        '[CONTENT_REDACTED]',
      );
      expect(
        (sanitized['nested'] as Map<String, Object?>)['status'],
        'request failed for [REDACTED_EMAIL]',
      );
    });

    test('redacts tokens, URL queries, and local user directory names', () {
      final sanitized = AppLogSanitizer.map(<String, Object?>{
        'message': 'Bearer abc.def.ghi token=super-secret '
            'https://example.com/fail?access_token=abc',
        'stack': r'C:\Users\Alice\project\lib\main.dart:20 '
            '/home/bob/neura/lib/main.dart:20',
      });

      expect(
        sanitized['message'],
        'Bearer [REDACTED] token=[REDACTED] '
            'https://example.com/fail?[REDACTED]',
      );
      expect(sanitized['stack'], contains(r'C:\Users\<user>\project'));
      expect(sanitized['stack'], contains('/home/<user>/neura'));
      expect(sanitized['stack'], isNot(contains('Alice')));
      expect(sanitized['stack'], isNot(contains('bob')));
    });

    test('bounds deep and oversized values while keeping JSON valid', () {
      Object? deep = 'leaf';
      for (var i = 0; i < 10; i += 1) {
        deep = <String, Object?>{'layer': deep};
      }
      final sanitized = AppLogSanitizer.map(<String, Object?>{
        'deep': deep,
        'many': List<int>.generate(100, (index) => index),
        'when': DateTime.utc(2026, 8, 15),
      });

      expect(
        (sanitized['many'] as List<Object?>).last,
        '[TRUNCATED]',
      );
      expect(sanitized['when'], '2026-08-15T00:00:00.000Z');
      expect(jsonEncode(sanitized), contains('[MAX_DEPTH]'));
    });
  });
}
