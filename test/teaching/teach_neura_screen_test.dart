import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/teaching/neura_teaching_preferences.dart';
import 'package:neuro_companion/teaching/neura_teaching_service.dart';
import 'package:neuro_companion/teaching/teach_neura_screen.dart';

class _Store implements NeuraTeachingStore {
  @override
  bool get authorityCurrent => true;

  NeuraTeachingPreferences value = const NeuraTeachingPreferences();
  int writes = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<NeuraTeachingPreferences> read(
          {required bool Function() stillAllowed}) async =>
      value;

  @override
  Future<void> write(NeuraTeachingPreferences next,
      {required bool Function() stillAllowed}) async {
    if (gate != null) await gate!.future;
    if (!stillAllowed()) throw StateError('Revoked');
    writes++;
    if (fail) throw StateError('Synthetic unconfirmed write');
    value = next;
  }
}

Future<void> _open(WidgetTester tester, NeuraTeachingService service,
    {GlobalKey<NavigatorState>? navigatorKey,
    bool observer = true,
    double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: observer ? [teachNeuraRouteObserver] : [],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: NeuraTeachScreen(service: service),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('proposal is exact and No performs no write', (tester) async {
    final store = _Store();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    expect(
        find.text('Proposed answer detail: ${NeuraAnswerDetail.brief.label}'),
        findsOneWidget);
    expect(store.writes, 0);
    await _tap(tester, find.text('No'));
    expect(find.text('Save preference'), findsNothing);
    expect(store.writes, 0);
    expect(service.current.answerDetail, isNull);
  });

  testWidgets('save, replace and remove each field independently',
      (tester) async {
    final store = _Store();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    await _tap(tester, find.text('Save preference'));
    await tester.pumpAndSettle();
    expect(store.value.answerDetail, NeuraAnswerDetail.brief);
    await _tap(tester, find.byKey(const ValueKey('plan-one')));
    await _tap(tester, find.text('Save preference'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('answer-detailed')));
    await _tap(tester, find.text('Save preference'));
    await tester.pumpAndSettle();
    expect(store.value.answerDetail, NeuraAnswerDetail.detailed);
    expect(store.value.planSize, NeuraPlanSize.one);
    await _tap(tester, find.byKey(const ValueKey('remove-answer')));
    await _tap(tester, find.text('Remove preference'));
    await tester.pumpAndSettle();
    expect(store.value.answerDetail, isNull);
    expect(store.value.planSize, NeuraPlanSize.one);
    await _tap(tester, find.byKey(const ValueKey('remove-plan')));
    await _tap(tester, find.text('Remove preference'));
    await tester.pumpAndSettle();
    expect(store.value.planSize, isNull);
  });

  testWidgets('Just today remains temporary and does not write storage',
      (tester) async {
    final store = _Store();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('plan-three')));
    await _tap(tester, find.text('Just today'));
    await tester.pumpAndSettle();
    expect(service.current.planSize, NeuraPlanSize.three);
    expect(service.planIsTemporary, isTrue);
    expect(store.writes, 0);
    await _tap(tester, find.byKey(const ValueKey('remove-plan')));
    await _tap(tester, find.text('Remove preference'));
    await tester.pumpAndSettle();
    expect(service.current.planSize, isNull);
  });

  testWidgets('background cancels a proposal without saving', (tester) async {
    final store = _Store();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('answer-balanced')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Save preference'), findsNothing);
    expect(store.writes, 0);
  });

  testWidgets('cover and uncover in the same frame revoke pending write',
      (tester) async {
    final store = _Store()..gate = Completer<void>();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    await _open(tester, service, navigatorKey: navigatorKey);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    await _tap(tester, find.text('Save preference'));
    unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered')))));
    navigatorKey.currentState!.pop();
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    expect(store.value.answerDetail, isNull);
    expect(find.text('Save preference'), findsNothing);
  });

  testWidgets('storage failure is unconfirmed and can be reviewed and retried',
      (tester) async {
    final store = _Store()..fail = true;
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    await _tap(tester, find.text('Save preference'));
    await tester.pumpAndSettle();
    expect(find.textContaining('outcome of this change is unconfirmed'),
        findsOneWidget);
    expect(find.text('Preference saved.'), findsNothing);
    store.fail = false;
    await _tap(tester, find.text('Review preferences'));
    await tester.pumpAndSettle();
    expect(service.loaded, isTrue);
    expect(find.textContaining('outcome of this change is unconfirmed'),
        findsNothing);
    expect(find.textContaining('Preferences could not be confirmed'),
        findsNothing);
    expect(find.text('Preference saved.'), findsNothing);
    expect(store.value.answerDetail, isNull);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    await _tap(tester, find.text('Save preference'));
    await tester.pumpAndSettle();
    expect(store.value.answerDetail, NeuraAnswerDetail.brief);
  });

  testWidgets('profile mode and missing route observer fail closed',
      (tester) async {
    final store = _Store();
    final service =
        NeuraTeachingService.forTesting(store: store, profileMode: () => true);
    addTearDown(service.dispose);
    await _open(tester, service);
    final button = tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('answer-brief')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('unavailable in Safe Mode'), findsOneWidget);
    expect(store.writes, 0);
    await tester.pumpWidget(const SizedBox());
    final available = NeuraTeachingService.forTesting(store: _Store());
    addTearDown(available.dispose);
    await _open(tester, available, observer: false);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('answer-brief')))
            .onPressed,
        isNull);
  });

  testWidgets('Safe Mode and recovery cancel proposals immediately',
      (tester) async {
    final store = _Store();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    addTearDown(() {
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
    });
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(find.text('Save preference'), findsNothing);
    SafeBoot.instance.safeMode.value = false;
    await _tap(tester, find.text('Review preferences'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('answer-detailed')));
    SafeBoot.instance.restartRequired.value = true;
    await tester.pump();
    expect(find.text('Save preference'), findsNothing);
    expect(store.writes, 0);
  });

  testWidgets('pending write disables duplicates and is revoked on disposal',
      (tester) async {
    final store = _Store()..gate = Completer<void>();
    final service = NeuraTeachingService.forTesting(store: store);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _tap(tester, find.byKey(const ValueKey('answer-brief')));
    await _tap(tester, find.text('Save preference'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save preference'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small window and large text remain scrollable without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = NeuraTeachingService.forTesting(store: _Store());
    addTearDown(service.dispose);
    await _open(tester, service, textScale: 2);
    await _tap(tester, find.byKey(const ValueKey('plan-one')));
    await _tap(tester, find.text('No'));
    expect(tester.takeException(), isNull);
  });
}
