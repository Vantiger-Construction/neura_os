import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/care/models/clinic_contact_draft.dart';
import 'package:neuro_companion/care/screens/care_mode_home_screen.dart';
import 'package:neuro_companion/care/screens/clinic_contact_screen.dart';
import 'package:neuro_companion/care/screens/neura_care_loop_screen.dart';
import 'package:neuro_companion/constitution/neura_constitution_service.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _portal = 'https://clinic.example.test/patient/login';
const _notes = 'Please help me arrange a routine appointment.';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <Map<Object?, Object?>>[];
  bool launchResult = true;
  bool launchThrows = false;
  Completer<bool>? pendingLaunch;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
        (call) async {
      if (call.method == 'launch') {
        launches.add(Map<Object?, Object?>.from(call.arguments as Map));
        if (launchThrows) throw PlatformException(code: 'synthetic-error');
        if (pendingLaunch != null) return pendingLaunch!.future;
        return launchResult;
      }
      throw StateError('Unexpected platform operation: ${call.method}');
    });
  });

  setUp(() async {
    launches.clear();
    launchResult = true;
    launchThrows = false;
    pendingLaunch = null;
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    NeuraConstitutionService.instance.resetAfterDataWipe();
    await NeuraConstitutionService.instance.save(
      const NeuraPersonalConstitution(allowExternalMessages: true),
    );
  });

  tearDownAll(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, null);
  });

  test('phone destination accepts ordinary numbers and rejects dial commands',
      () {
    expect(ClinicContactDraft.phoneUri('+1 (202) 555-0123').toString(),
        'tel:+12025550123');
    for (final value in [
      '*123#',
      '911',
      '2025550123;123',
      '2025550123,123',
      '2025550123?body=private',
      '2025550123%3B123',
      '2025550123ext4',
      '++12025550123',
      '1234567890123456',
      '',
    ]) {
      expect(ClinicContactDraft.phoneUri(value), isNull, reason: value);
    }
  });

  test('portal address rejects credential, payload and local URL forms', () {
    expect(ClinicContactDraft.portalUri(_portal).toString(), _portal);
    for (final value in [
      'http://clinic.example.test',
      'javascript:alert(1)',
      'https://user:password@clinic.example.test',
      'https://clinic.example.test?name=Alex',
      'https://clinic.example.test/#private',
      'https://clinic.example.test?',
      'https://127.0.0.1',
      'https://[::1]',
      'https://localhost',
      'https://clinic.local',
      'https://clinic.example.test:8443',
      'https://-clinic.example.test',
      'https://clinic..example.test',
      '',
    ]) {
      expect(ClinicContactDraft.portalUri(value), isNull, reason: value);
    }
  });

  Future<void> fillDraft(WidgetTester tester, {bool phone = false}) async {
    if (phone) {
      await tester.tap(find.text('Phone call brief'));
      await tester.pump();
    }
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alex Example');
    await tester.enterText(fields.at(1), 'Example Clinic');
    await tester.enterText(fields.at(2), phone ? '+1 (202) 555-0123' : _portal);
    await tester.enterText(fields.at(3), _notes);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Prepare locally'));
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester, {bool phone = false}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const MaterialApp(home: ClinicContactScreen.previewForTesting()));
    await fillDraft(tester, phone: phone);
  }

  Future<void> review(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Review external handoff'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Review external handoff'));
    await tester.pumpAndSettle();
  }

  testWidgets('local draft uses only typed details with honest capability text',
      (tester) async {
    final keys = NeuraPrefsCache.prefs.getKeys();
    await prepare(tester);
    final message =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(message, contains('From: Alex Example'));
    expect(message, contains('To: Example Clinic'));
    expect(message, contains(_notes));
    expect(message, contains('AI assistant'));
    expect(find.textContaining('are not connected yet'), findsOneWidget);
    expect(NeuraPrefsCache.prefs.getKeys(), keys);
    expect(launches, isEmpty);
  });

  testWidgets('cancel sends nothing; approval opens only the exact portal URL',
      (tester) async {
    await prepare(tester);
    await review(tester);
    expect(find.text('Destination: $_portal'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launches, isEmpty);
    await review(tester);
    await tester.tap(find.text('Open clinic portal'));
    await tester.pumpAndSettle();
    expect(launches, hasLength(1));
    expect(launches.single['url'], _portal);
    expect(launches.single['useWebView'], false);
    expect(launches.single['useSafariVC'], false);
    expect(launches.single['headers'], isEmpty);
    expect(find.textContaining('No clinic response or delivery is confirmed'),
        findsOneWidget);
    await review(tester);
    expect(launches, hasLength(1)); // A second attempt needs a new preview.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('phone handoff contains no patient name, notes or call audio',
      (tester) async {
    await prepare(tester, phone: true);
    await review(tester);
    expect(find.textContaining('Neura does not join'), findsOneWidget);
    await tester.tap(find.text('Open phone app'));
    await tester.pumpAndSettle();
    expect(launches.single['url'], 'tel:+12025550123');
    expect(launches.single.toString(), isNot(contains('Alex')));
    expect(launches.single.toString(), isNot(contains(_notes)));
  });

  testWidgets('changed destination invalidates draft and contact confirmation',
      (tester) async {
    await prepare(tester);
    await tester.enterText(
        find.byType(TextFormField).at(2), 'https://another.example.test/login');
    await tester.pump();
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
    await tester.tap(find.text('Prepare locally'));
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Review external handoff'));
    expect(button.onPressed, isNull);
    expect(launches, isEmpty);
  });

  testWidgets('default personal constitution blocks external handoff',
      (tester) async {
    await NeuraConstitutionService.instance
        .save(const NeuraPersonalConstitution());
    await prepare(tester);
    await review(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.textContaining('External messages are disabled'), findsOneWidget);
    expect(launches, isEmpty);
  });

  testWidgets('a policy change while preview is open revokes approval',
      (tester) async {
    await prepare(tester);
    await review(tester);
    await NeuraConstitutionService.instance
        .save(const NeuraPersonalConstitution());
    await tester.tap(find.text('Open clinic portal'));
    await tester.pumpAndSettle();
    expect(launches, isEmpty);
  });

  testWidgets(
      'Safe Mode removes open review and clears temporary health details',
      (tester) async {
    await prepare(tester);
    await review(tester);
    SafeBoot.instance.safeMode.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    for (final field
        in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.controller!.text, isEmpty);
    }
    expect(find.textContaining('Safe Mode: external handoff is disabled'),
        findsOneWidget);
    expect(launches, isEmpty);
    await tester.pumpWidget(const SizedBox());
    SafeBoot.instance.safeMode.value = false;
  });

  testWidgets('background removes preview and draft; returning never launches',
      (tester) async {
    await prepare(tester);
    await review(tester);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('Temporary clinic details and draft cleared'),
        findsOneWidget);
    expect(launches, isEmpty);
  });

  testWidgets('transient inactivity invalidates the review before returning',
      (tester) async {
    await prepare(tester);
    await review(tester);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(launches, isEmpty);
  });

  testWidgets('an expired preview cannot launch an external app',
      (tester) async {
    await prepare(tester);
    await review(tester);
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Review expired'), findsOneWidget);
    expect(launches, isEmpty);
  });

  testWidgets('failed platform handoff never reports clinic delivery',
      (tester) async {
    launchResult = false;
    await prepare(tester);
    await review(tester);
    await tester.tap(find.text('Open clinic portal'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Could not open an external app'), findsOneWidget);
    expect(launches, hasLength(1));
  });

  testWidgets('platform error does not retry or expose the exception',
      (tester) async {
    launchThrows = true;
    await prepare(tester);
    await review(tester);
    await tester.tap(find.text('Open clinic portal'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Handoff could not be confirmed'), findsOneWidget);
    expect(find.textContaining('synthetic-error'), findsNothing);
    expect(launches, hasLength(1));
  });

  testWidgets('late platform completion cannot restore cleared draft or status',
      (tester) async {
    pendingLaunch = Completer<bool>();
    await prepare(tester);
    await review(tester);
    await tester.tap(find.text('Open clinic portal'));
    await tester.pump();
    await tester.tap(find.text('Clear temporary details'));
    await tester.pump();
    pendingLaunch!.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('Temporary clinic details and draft cleared'),
        findsOneWidget);
    expect(find.textContaining('External app opened'), findsNothing);
    expect(launches, hasLength(1));
  });

  testWidgets(
      'closing and reopening does not restore a previous person’s draft',
      (tester) async {
    await prepare(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
        const MaterialApp(home: ClinicContactScreen.previewForTesting()));
    await tester.pumpAndSettle();
    for (final field
        in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.controller!.text, isEmpty);
    }
    expect(find.byType(SelectableText), findsNothing);
    expect(launches, isEmpty);
  });

  for (final safeMode in [false, true]) {
    testWidgets(
        'late handoff completion cannot restore details after '
        '${safeMode ? 'Safe Mode' : 'background and resume'}', (tester) async {
      pendingLaunch = Completer<bool>();
      await prepare(tester);
      await review(tester);
      await tester.tap(find.text('Open clinic portal'));
      await tester.pump();
      expect(launches, hasLength(1));
      if (safeMode) {
        SafeBoot.instance.safeMode.value = true;
      } else {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pump();
      pendingLaunch!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      for (final field
          in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
        expect(field.controller!.text, isEmpty);
      }
      expect(find.textContaining('Temporary clinic details and draft cleared'),
          findsOneWidget);
      expect(find.textContaining('External app opened'), findsNothing);
      expect(launches, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      SafeBoot.instance.safeMode.value = false;
    });
  }

  testWidgets('a pending handoff cannot revive a disposed preview',
      (tester) async {
    pendingLaunch = Completer<bool>();
    await prepare(tester);
    await review(tester);
    await tester.tap(find.text('Open clinic portal'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: ClinicContactScreen()));
    pendingLaunch!.complete(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Clinic contact is on hold.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('External app opened'), findsNothing);
    expect(launches, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the preparation route also removes its private review',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Home')),
    ));
    final route = MaterialPageRoute<void>(
        builder: (_) => const ClinicContactScreen.previewForTesting());
    unawaited(navigator.currentState!.push(route));
    await tester.pumpAndSettle();
    await fillDraft(tester);
    await review(tester);
    expect(find.text('Destination: $_portal'), findsOneWidget);
    navigator.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining(_notes), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(launches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message and review fit a narrow mobile screen with larger text',
      (tester) async {
    await prepare(tester);
    await tester.binding.setSurfaceSize(const Size(360, 740));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: const ClinicContactScreen.previewForTesting(),
    ));
    await tester.pumpAndSettle();
    await review(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launches, isEmpty);
  });

  testWidgets('held screen blocks preparation even when sharing is permitted',
      (tester) async {
    final keys = NeuraPrefsCache.prefs.getKeys();
    await tester.pumpWidget(const MaterialApp(home: ClinicContactScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Clinic contact is on hold.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Prepare locally'), findsNothing);
    expect(find.text('Review external handoff'), findsNothing);
    SafeBoot.instance.safeMode.value = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(NeuraPrefsCache.prefs.getKeys(), keys);
    expect(
        NeuraConstitutionService.instance.current.allowExternalMessages, true);
    expect(launches, isEmpty);
  });

  testWidgets('Care Loop does not expose held clinic contact', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NeuraCareLoopScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Doctor & clinic'), findsNothing);
    expect(find.text('Help me through this'), findsOneWidget);
    expect(launches, isEmpty);
  });

  testWidgets('Care Mode does not expose held clinic contact', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CareModeHomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Doctor & clinic'), findsNothing);
    expect(find.text('Trusted Contacts'), findsOneWidget);
    expect(launches, isEmpty);
  });
}
