import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/care/screens/care_mode_home_screen.dart';
import 'package:neuro_companion/care/screens/clinic_contact_screen.dart';
import 'package:neuro_companion/care/screens/neura_care_loop_screen.dart';
import 'package:neuro_companion/care/services/clinic_contact_route_observer.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/src/app.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/startup/startup_access_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('an untracked navigator keeps clinic preparation disabled',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: ClinicContactScreen(
      loadCheckIns: () async {
        reads++;
        return [];
      },
    )));
    await tester.pumpAndSettle();
    for (final field
        in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
      expect(field.enabled, false);
    }
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Prepare locally'))
            .onPressed,
        isNull);
    expect(reads, 0);
  });

  for (final entry in <String, Widget>{
    'Care Loop': const NeuraCareLoopScreen(),
    'Care Mode': const CareModeHomeScreen(),
  }.entries) {
    testWidgets('production navigator admits ${entry.key} clinic preparation',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_ProductionNavigatorFixture(home: entry.value));
      await tester.pumpAndSettle();
      expect(clinicContactRouteObserver.navigator,
          same(NeuroCompanionApp.navigatorKey.currentState));
      await tester.tap(find.text('Doctor & clinic'));
      await tester.pumpAndSettle();
      for (final field
          in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
        expect(field.enabled, true);
      }
      for (final (index, value) in [
        'Alex Example',
        'Example Clinic',
        '',
        'https://clinic.example.invalid/login',
        'TEST ONLY — a fictional question',
        '',
      ].indexed) {
        await tester.enterText(find.byType(TextFormField).at(index), value);
      }
      await tester.ensureVisible(find.text('Prepare locally'));
      await tester.tap(find.text('Prepare locally'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('No clinic has been contacted'), findsOneWidget);
      final navigator = NeuroCompanionApp.navigatorKey.currentState!;
      final covered = navigator.push<void>(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Synthetic cover'))));
      navigator.pop();
      await covered;
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Editable clinic report'),
          findsNothing);
      expect(find.textContaining('Temporary clinic details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Use the actual app builder's navigator configuration, replacing only the
/// startup/home and shell so this contract test cannot start live services.
/// In particular, the harness never supplies its own clinic observer list.
class _ProductionNavigatorFixture extends NeuroCompanionApp {
  const _ProductionNavigatorFixture({required this.home});
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final access = super.build(context) as StartupAccessGate;
    final owner = access.ownerBuilder(false) as StatelessWidget;
    final root = owner.build(context) as ValueListenableBuilder<HumanPrefs>;
    final configured =
        root.builder(context, root.valueListenable.value, null) as MaterialApp;
    return MaterialApp(
      navigatorKey: configured.navigatorKey,
      navigatorObservers: configured.navigatorObservers!,
      home: home,
    );
  }
}
