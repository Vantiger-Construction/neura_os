import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_offline_budget.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_error_pipeline.dart';
import 'package:neuro_companion/widgets/neura_offline_controls.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/engine_synthetic_session');
  late List<MethodCall> diagnosticCalls;
  late Map<String, int> snapshot;
  Completer<Map<String, int>>? delayed;
  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraErrorPipeline.instance.clearFatalError();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    diagnosticCalls = [];
    delayed = null;
    snapshot = {
      'version': 1,
      'daemon': 1,
      'daemonVersion': 1,
      'model': 1,
      'memory': 1,
      'totalMiB': 8192,
      'availableMiB': 4096,
    };
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      diagnosticCalls.add(call);
      if (call.method == 'beginOllamaReadiness') return 1;
      if (call.method == 'pollOllamaReadiness') {
        return delayed?.future ?? snapshot;
      }
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraErrorPipeline.instance.clearFatalError();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Future<void> controls(WidgetTester tester) async {
    final adapter = NeuraOllamaChat(supported: true);
    addTearDown(adapter.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NeuraOfflineControls(
          budget: NeuraOfflineBudget.compact,
          readiness: adapter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> check(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Check offline readiness'));
    await tester.tap(find.text('Check offline readiness'));
    await tester.pumpAndSettle();
  }

  testWidgets('no automatic probe; a backgrounded RAM result is discarded', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<Map<String, int>>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      calls++;
      expect(call.method, 'readOfflineMemory');
      return pending.future;
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: NeuraOfflineControls(budget: NeuraOfflineBudget.compact),
      ),
    );
    expect(calls, 0);
    await tester.tap(find.text('Check available RAM'));
    await tester.pump();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pending.complete({'totalMiB': 8192, 'availableMiB': 4096});
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('4096 MiB'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets(
    'explicit readiness shows each prerequisite without starting speech',
    (tester) async {
      await controls(tester);
      expect(diagnosticCalls, isEmpty);
      await check(tester);
      expect(
        find.text('Offline prerequisites met at this moment.'),
        findsOneWidget,
      );
      expect(find.textContaining('Ollama: available'), findsOneWidget);
      expect(find.textContaining('Supported stable release'), findsOneWidget);
      expect(
        find.textContaining('Verified local qwen3:4b-instruct'),
        findsOneWidget,
      );
      expect(
        find.textContaining('4096 MiB available of 8192 MiB'),
        findsOneWidget,
      );
      expect(find.textContaining('Test your microphone'), findsOneWidget);
      expect(diagnosticCalls.map((c) => c.method), [
        'beginOllamaReadiness',
        'pollOllamaReadiness',
        'cancelOllama',
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final problem in ['daemon', 'version', 'missing', 'memory']) {
    testWidgets(
      '$problem failure offers a manual next step and keeps check explicit',
      (tester) async {
        final text = switch (problem) {
          'daemon' => 'Install and open Ollama yourself',
          'version' => 'Update Ollama to a stable release',
          'missing' => 'ollama pull qwen3:4b-instruct',
          _ => 'Close other apps',
        };
        switch (problem) {
          case 'daemon':
            snapshot.addAll({'daemon': 2, 'daemonVersion': 0, 'model': 0});
            break;
          case 'version':
            snapshot.addAll({'daemonVersion': 2, 'model': 0});
            break;
          case 'missing':
            snapshot['model'] = 2;
            break;
          case 'memory':
            snapshot.addAll({'memory': 2, 'availableMiB': 2048});
            break;
        }
        await controls(tester);
        await check(tester);
        expect(
          find.text('Offline prerequisites are incomplete.'),
          findsOneWidget,
        );
        expect(find.textContaining(text), findsOneWidget);
        expect(
          diagnosticCalls.where((c) => c.method == 'beginOllama'),
          isEmpty,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(
          diagnosticCalls.where((c) => c.method == 'beginOllamaReadiness'),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final reason in ['cancel', 'background', 'close', 'safe', 'recovery']) {
    testWidgets(
      '$reason discards a pending readiness result and never resumes',
      (tester) async {
        delayed = Completer<Map<String, int>>();
        await controls(tester);
        await check(tester);
        expect(find.text('Checking local prerequisites…'), findsOneWidget);
        switch (reason) {
          case 'cancel':
            await tester.ensureVisible(find.text('Cancel check'));
            await tester.tap(find.text('Cancel check'));
            break;
          case 'background':
            binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            break;
          case 'close':
            await tester.pumpWidget(const SizedBox());
            break;
          case 'safe':
            SafeBoot.instance.safeMode.value = true;
            break;
          case 'recovery':
            NeuraErrorPipeline.instance.fatalError.value =
                const NeuraFatalError(source: 'synthetic', phase: 'runtime');
            break;
        }
        delayed!.complete(snapshot);
        await tester.pumpAndSettle();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        SafeBoot.instance.safeMode.value = false;
        NeuraErrorPipeline.instance.clearFatalError();
        await tester.pumpAndSettle();
        expect(
          find.text('Offline prerequisites met at this moment.'),
          findsNothing,
        );
        expect(
          diagnosticCalls.where((c) => c.method == 'beginOllamaReadiness'),
          hasLength(1),
        );
        expect(
          diagnosticCalls.where((c) => c.method == 'cancelOllama'),
          isNotEmpty,
        );
        if (reason == 'safe' || reason == 'recovery') {
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Check offline readiness'),
                )
                .onPressed,
            isNull,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
