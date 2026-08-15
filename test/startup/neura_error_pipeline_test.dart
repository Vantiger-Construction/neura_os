import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/main.dart' as neura_main;
import 'package:neuro_companion/startup/neura_error_pipeline.dart';
import 'package:neuro_companion/startup/neura_error_redactor.dart';

void main() {
  final pipeline = NeuraErrorPipeline.instance;

  setUp(pipeline.resetForTesting);

  test('redacts credentials, sensitive URL values, and user paths', () {
    const raw = 'authorization=top-secret '
        '{"api_key":"json-private"} '
        'Bearer abc.def.ghi '
        'sk-'
        'live-'
        '0123456789abcdef '
        'ghp_'
        '0123456789abcdefghijklmnop '
        'sbp_'
        '0123456789abcdefghijklmnop '
        'eyJhbGciOiJIUzI1NiJ9.'
        'eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
        'abcdefghijklmnopqrstuv '
        'alex'
        '@example.test '
        'https://example.test/callback?code=private-code&mode=1 '
        r'C:\Users\alex\AppData\Local '
        r'C:\Users\Mary Jane\Documents '
        '/home/jamie/neura '
        '/Users/Mary Jane/Library';

    final sanitized = NeuraErrorRedactor.message(raw);

    expect(sanitized, isNot(contains('top-secret')));
    expect(sanitized, isNot(contains('json-private')));
    expect(sanitized, isNot(contains('abc.def.ghi')));
    expect(sanitized, isNot(contains('0123456789abcdef')));
    expect(sanitized, isNot(contains('0123456789abcdefghijklmnop')));
    expect(sanitized, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
    expect(sanitized, isNot(contains('alex@example.test')));
    expect(sanitized, isNot(contains('private-code')));
    expect(sanitized, isNot(contains(r'Users\alex')));
    expect(sanitized, isNot(contains('/home/jamie')));
    expect(sanitized, isNot(contains('Mary Jane')));
    expect(sanitized, contains('<redacted>'));
  });

  test('hands stable structured payloads to one AppLog sink', () async {
    final captured = <Map<String, Object?>>[];
    await pipeline.attachAppLog((payload) async => captured.add(payload));

    pipeline.capture(
      StateError('api_key=do-not-store'),
      StackTrace.fromString(r'C:\Users\alex\neura\main.dart:1'),
      source: 'test_source',
      fatal: false,
      phase: 'runtime',
    );
    await pipeline.attachAppLog((payload) async => captured.add(payload));

    expect(captured, hasLength(1));
    expect(
      captured.single.keys.toSet(),
      equals({
        'source',
        'error_type',
        'message',
        'stack',
        'fatal',
        'phase',
      }),
    );
    expect(captured.single['source'], 'test_source');
    expect(captured.single['error_type'], 'StateError');
    expect(
      captured.single['message'],
      'An unexpected StateError was contained.',
    );
    expect(captured.single['stack'], isNot(contains(r'Users\alex')));
    expect(captured.single['fatal'], isFalse);
    expect(captured.single['phase'], 'runtime');
  });

  test(
    'deduplicates the same error delivered by multiple root handlers',
    () async {
      final captured = <Map<String, Object?>>[];
      await pipeline.attachAppLog((payload) async => captured.add(payload));
      final stack = StackTrace.fromString('frame one\nframe two');

      pipeline.capture(
        StateError('same failure'),
        stack,
        source: 'platform_dispatcher',
        fatal: true,
        phase: 'runtime',
      );
      pipeline.capture(
        StateError('same failure'),
        stack,
        source: 'root_isolate',
        fatal: true,
        phase: 'runtime',
      );
      await pipeline.attachAppLog((payload) async => captured.add(payload));

      expect(captured, hasLength(1));
      expect(pipeline.fatalError.value, isNotNull);
    },
  );

  test(
    'a fatal delivery is not suppressed by an earlier nonfatal one',
    () async {
      final captured = <Map<String, Object?>>[];
      await pipeline.attachAppLog((payload) async => captured.add(payload));
      final stack = StackTrace.fromString('shared frame');

      pipeline.capture(
        StateError('content is not persisted'),
        stack,
        source: 'framework',
        fatal: false,
        phase: 'runtime',
      );
      pipeline.capture(
        StateError('content is not persisted'),
        stack,
        source: 'root_zone',
        fatal: true,
        phase: 'runtime',
      );
      await pipeline.attachAppLog((payload) async => captured.add(payload));

      expect(captured, hasLength(2));
      expect(
        captured.map((record) => record['fatal']),
        containsAll([false, true]),
      );
      expect(pipeline.fatalError.value, isNotNull);
    },
  );

  test(
    'supports removable sanitized observers without replacing handlers',
    () async {
      await pipeline.attachAppLog((_) async {});
      Map<String, Object?>? observed;
      final remove = pipeline.addObserver((payload) => observed = payload);

      pipeline.capture(
        StateError('password=private-value'),
        StackTrace.fromString('first frame'),
        source: 'observer_test',
        fatal: false,
        phase: 'runtime',
      );
      expect(observed, isNotNull);
      expect(observed!['message'], isNot(contains('private-value')));

      observed = null;
      remove();
      pipeline.capture(
        StateError('different error'),
        StackTrace.fromString('different frame'),
        source: 'observer_test',
        fatal: false,
        phase: 'runtime',
      );
      expect(observed, isNull);
    },
  );

  testWidgets('fatal error renders recovery and can continue safely', (
    tester,
  ) async {
    await pipeline.attachAppLog((_) async {});
    var safeModeRequested = false;

    await tester.pumpWidget(
      NeuraErrorBoundary(
        onContinueInSafeMode: () => safeModeRequested = true,
        child: const MaterialApp(home: Text('normal app')),
      ),
    );
    expect(find.text('normal app'), findsOneWidget);

    pipeline.capture(
      StateError('contained'),
      StackTrace.current,
      source: 'test',
      fatal: true,
      phase: 'runtime',
    );
    await tester.pump();

    expect(find.text('Neura entered recovery mode'), findsOneWidget);
    await tester.tap(find.text('Continue in Safe Mode'));
    await tester.pump();

    expect(safeModeRequested, isTrue);
    expect(find.text('normal app'), findsOneWidget);
  });

  test('native bootstrap retry succeeds after a transient failure', () async {
    var calls = 0;
    final result = await neura_main.retryBootstrapOperation<int>(
      () async {
        calls += 1;
        if (calls < 3) throw StateError('plugin not registered yet');
        return 7;
      },
      attempts: 3,
      timeout: const Duration(seconds: 1),
      retryDelay: Duration.zero,
    );

    expect(result, 7);
    expect(calls, 3);
  });

  test('launch smoke mode requires the exact native-only argument', () {
    expect(neura_main.kLaunchSmokeTestSuccessExitCode, 73);
    expect(neura_main.kLaunchSmokeTestSuccessExitCode, isNot(0));
    expect(
      neura_main.launchSmokeTestRequested(
        const [neura_main.kLaunchSmokeTestArgument],
        isWeb: false,
      ),
      isTrue,
    );
    expect(
      neura_main.launchSmokeTestRequested(
        const [neura_main.kLaunchSmokeTestArgument],
        isWeb: true,
      ),
      isFalse,
    );
    expect(
      neura_main.launchSmokeTestRequested(
        const ['--launch-smoke-test=true'],
        isWeb: false,
      ),
      isFalse,
    );
    expect(
      neura_main.launchSmokeTestRequested(
        const ['--unrelated'],
        isWeb: false,
      ),
      isFalse,
    );
  });

  test('native bootstrap retry is bounded', () async {
    var calls = 0;
    await expectLater(
      neura_main.retryBootstrapOperation<void>(
        () {
          calls += 1;
          return Completer<void>().future;
        },
        attempts: 2,
        timeout: const Duration(milliseconds: 5),
        retryDelay: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 2);
  });
}
