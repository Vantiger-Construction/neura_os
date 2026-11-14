import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/guided_support_screen.dart';
import 'package:neuro_companion/modules/support/human_support_screen.dart';
import 'package:neuro_companion/modules/support/wellbeing_home_card.dart';
import 'package:neuro_companion/modules/support/wellbeing_session_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  void resume() {
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  void background() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  String? copied;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    resume();
    copied = null;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    resume();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pump();
  }

  testWidgets('home offers three choices without loading private storage',
      (tester) async {
    await pump(
        tester,
        const Scaffold(
            body: SingleChildScrollView(child: WellbeingHomeCard())));
    expect(find.text('Help me settle'), findsOneWidget);
    expect(find.text('Help me take one step'), findsOneWidget);
    expect(find.text('Help me reach someone'), findsOneWidget);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
    await tap(tester, 'Help me take one step');
    await tester.pumpAndSettle();
    expect(find.byType(WellbeingSessionScreen), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
  });

  testWidgets('home handles narrow width and enlarged text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: child!),
        home: const Scaffold(
            body: SingleChildScrollView(child: WellbeingHomeCard()))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Urgent help and crisis contacts'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('five minute timer completes silently and only after starting',
      (tester) async {
    var now = DateTime(2026, 11, 14, 12);
    await pump(tester, WellbeingSessionScreen(now: () => now));
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('Five minutes are up'), findsNothing);
    await tap(tester, 'Try a five-minute timer (optional)');
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(find.textContaining('Five minutes are up'), findsOneWidget);
    expect(copied, isNull);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets('stop clears writing and cancels completion', (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic small step');
    await tap(tester, 'Try a five-minute timer (optional)');
    await tap(tester, 'Stop and clear');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('Five minutes are up'), findsNothing);
  });

  testWidgets('background stops timer and does not restart on return',
      (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic private draft');
    await tap(tester, 'Try a five-minute timer (optional)');
    background();
    await tester.pump();
    resume();
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('Five minutes are up'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets('covered route stops timer and clears draft', (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic draft');
    await tap(tester, 'Try a five-minute timer (optional)');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover'))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 6));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.textContaining('Five minutes are up'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets('safety transition cancels active timer', (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tap(tester, 'Try a five-minute timer (optional)');
    SafeBoot.instance.safeMode.value = true;
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('Five minutes are up'), findsNothing);
    expect(find.textContaining('Stopped.'), findsOneWidget);
  });

  test('quiet hours cover midnight, daytime, exact boundaries and all day', () {
    expect(wellbeingQuietHours(22, 22, 8), isTrue);
    expect(wellbeingQuietHours(7, 22, 8), isTrue);
    expect(wellbeingQuietHours(8, 22, 8), isFalse);
    expect(wellbeingQuietHours(12, 9, 17), isTrue);
    expect(wellbeingQuietHours(17, 9, 17), isFalse);
    expect(wellbeingQuietHours(12, 8, 8), isTrue);
  });

  testWidgets('quiet hours prevent starting a reminder', (tester) async {
    await pump(
        tester,
        WellbeingSessionScreen(
            reminder: true, now: () => DateTime(2026, 11, 14, 23)));
    await tap(tester, 'Start this reminder');
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('no reminder started'), findsOneWidget);
    expect(find.textContaining('A gentle invitation:'), findsNothing);
  });

  testWidgets('entering quiet hours cancels an admitted reminder',
      (tester) async {
    var now = DateTime(2026, 11, 14, 21, 59);
    await pump(tester, WellbeingSessionScreen(reminder: true, now: () => now));
    await tap(tester, 'Start this reminder');
    now = DateTime(2026, 11, 14, 22);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 6));
    expect(find.text('Quiet hours: reminder stopped.'), findsOneWidget);
    expect(find.textContaining('A gentle invitation:'), findsNothing);
  });

  testWidgets('daytime reminder completes once without storing preferences',
      (tester) async {
    var now = DateTime(2026, 11, 14, 12);
    await pump(tester, WellbeingSessionScreen(reminder: true, now: () => now));
    await tap(tester, 'Start this reminder');
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(find.textContaining('A gentle invitation:'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets('covering a human-support draft clears it without copying',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic private message');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover'))));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(copied, isNull);
  });

  testWidgets(
      'guided writing opens manual human support with no draft transfer',
      (tester) async {
    await pump(
        tester,
        const GuidedSupportScreen(
            initialActivity: GuidedSupportActivity.quietWriting));
    await tester.enterText(
        find.byType(TextField), 'Synthetic private reflection');
    await tap(tester, 'Reach a person');
    await tester.pumpAndSettle();
    expect(find.byType(HumanSupportScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Call or text 988'), findsNothing);
    expect(copied, isNull);
  });

  testWidgets('human support never guesses a country and works offline',
      (tester) async {
    await pump(tester, const HumanSupportScreen(urgentOnly: true));
    expect(find.text('Call or text 988'), findsNothing);
    expect(find.text('Call or text 9-8-8'), findsNothing);
    await tap(tester, 'Canada');
    await tester.pumpAndSettle();
    expect(find.text('Call or text 9-8-8'), findsOneWidget);
    expect(find.text('Immediate danger: 911.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets('draft copies only on request and clears on background',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(
        find.byType(TextField), 'Synthetic reviewed message');
    expect(copied, isNull);
    await tap(tester, 'Copy reviewed draft');
    expect(copied, 'Synthetic reviewed message');
    background();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(copied, 'Synthetic reviewed message');
  });

  testWidgets('breathing is optional, self paced and stoppable',
      (tester) async {
    await pump(
        tester,
        const GuidedSupportScreen(
            initialActivity: GuidedSupportActivity.gentleBreathing));
    expect(find.text('Get comfortable'), findsOneWidget);
    await tap(tester, 'Next step');
    expect(find.textContaining('Do not force a deep breath or hold it.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Stop activity'));
    await tester.pumpAndSettle();
    expect(find.text('What would help right now?'), findsOneWidget);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });
}
