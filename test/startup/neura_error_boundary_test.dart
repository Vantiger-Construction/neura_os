import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';

void main() {
  final pipeline = NeuraErrorPipeline.instance;

  setUp(() {
    pipeline.resetForTesting();
  });

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

    pipeline.resetForTesting();
  });
}
