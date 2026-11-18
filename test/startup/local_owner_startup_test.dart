import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/config/supabase_config.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/local_owner_password_screen.dart';
import 'package:neuro_companion/screens/sign_in_screen.dart';
import 'package:neuro_companion/screens/verify_email_screen.dart';
import 'package:neuro_companion/services/app_lock_prefs.dart';
import 'package:neuro_companion/services/local_owner_login.dart';
import 'package:neuro_companion/startup/neura_boot_screen.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/startup/neura_startup_coordinator.dart';
import 'package:neuro_companion/widgets/auth_guard.dart';

class _CompletedBoot extends Fake implements NeuraStartupCoordinator {
  _CompletedBoot({this.supabaseInitialized = true});

  @override
  final bool supabaseInitialized;
  @override
  final ready = ValueNotifier(true);
  @override
  final booting = ValueNotifier(false);
  @override
  final stage = ValueNotifier(const NeuraBootStage('Ready', 1));
  @override
  final failure = ValueNotifier<NeuraBootFailure?>(null);
  @override
  Future<void> boot() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool originalSafeMode;
  late bool originalLock;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    originalSafeMode = SafeBoot.instance.safeMode.value;
    originalLock = AppLockPrefsController.instance.enabled.value;
    SafeBoot.instance.safeMode.value = false;
    AppLockPrefsController.instance.enabled.value = false;
    await NeuraPrefsCache.prefs.clear();
  });

  tearDown(() {
    SafeBoot.instance.safeMode.value = originalSafeMode;
    AppLockPrefsController.instance.enabled.value = originalLock;
  });

  test('configured CI fixture really includes optional backend settings', () {
    if (const bool.fromEnvironment('NEURA_EXPECT_CONFIGURED_STARTUP')) {
      expect(SupabaseConfig.isConfigured, isTrue);
    }
  });

  for (final initialized in [true, false]) {
    testWidgets(
        'signed-out owner reaches local setup with backend initialized=$initialized',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: NeuraBootScreen(
              coordinator: _CompletedBoot(supabaseInitialized: initialized),
              home: const Scaffold(body: Text('Synthetic local workspace')))));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(VerifyEmailScreen), findsNothing);
      expect(find.byType(LocalOwnerPasswordScreen), findsOneWidget);
      await tester.tap(find.text('Continue without an owner password'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic local workspace'), findsOneWidget);
      expect(NeuraPrefsCache.prefs.getBool(LocalOwnerLogin.setupDismissedKey),
          isTrue);
    });
  }

  testWidgets('a returning owner is not given another account login or setup',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: NeuraBootScreen(
            hasOwnerPassword: true,
            coordinator: _CompletedBoot(),
            home: const Scaffold(body: Text('Synthetic local workspace')))));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic local workspace'), findsOneWidget);
    expect(find.byType(LocalOwnerPasswordScreen), findsNothing);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('the saved skip choice persists without a cloud account',
      (tester) async {
    await NeuraPrefsCache.prefs
        .setBool(LocalOwnerLogin.setupDismissedKey, true);
    await tester.pumpWidget(MaterialApp(
        home: NeuraBootScreen(
            coordinator: _CompletedBoot(),
            home: const Scaffold(body: Text('Synthetic local workspace')))));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic local workspace'), findsOneWidget);
    expect(find.byType(LocalOwnerPasswordScreen), findsNothing);
  });

  testWidgets('an enabled device lock still blocks the owner destination',
      (tester) async {
    AppLockPrefsController.instance.enabled.value = true;
    await tester.pumpWidget(MaterialApp(
        home: NeuraBootScreen(
            coordinator: _CompletedBoot(),
            home: const Scaffold(body: Text('Synthetic local workspace')))));
    await tester.pumpAndSettle();
    expect(find.byType(AuthGuard), findsOneWidget);
    expect(find.text('Synthetic local workspace'), findsNothing);
    expect(find.byType(LocalOwnerPasswordScreen), findsNothing);
  });

  testWidgets('Safe Mode stays local and does not offer password enrolment',
      (tester) async {
    SafeBoot.instance.safeMode.value = true;
    await tester.pumpWidget(MaterialApp(
        home: NeuraBootScreen(
            coordinator: _CompletedBoot(),
            home: const Scaffold(body: Text('Synthetic local workspace')))));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic local workspace'), findsOneWidget);
    expect(find.byType(LocalOwnerPasswordScreen), findsNothing);
    expect(find.byType(SignInScreen), findsNothing);
  });
}
