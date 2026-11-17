import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/screens/local_owner_password_screen.dart';
import 'package:neuro_companion/screens/sign_in_screen.dart';
import 'package:neuro_companion/screens/sign_up_screen.dart';
import 'package:neuro_companion/services/local_owner_login.dart';
import 'package:neuro_companion/startup/startup_access_gate.dart';

class _ExistingOwner extends Fake implements LocalOwnerLogin {
  int reads = 0;
  bool failRead = false;
  bool? savedPreference;

  @override
  Future<void> create(String password, {required bool remember}) async {
    savedPreference = remember;
  }

  @override
  Future<bool> unlockRemembered(Future<bool> Function() verifyDevice) =>
      verifyDevice();

  @override
  Future<bool?> remembered() async {
    reads++;
    if (failRead) throw StateError('synthetic storage failure');
    return false;
  }

  @override
  Future<bool> unlock(String password, {required bool remember}) async =>
      password == 'synthetic owner phrase';
}

void main() {
  testWidgets(
      'guest can leave and return without reading or mounting the owner',
      (tester) async {
    final login = _ExistingOwner();
    var ownerBuilds = 0;
    await tester.pumpWidget(StartupAccessGate(
        login: login,
        ownerBuilder: (_) {
          ownerBuilds++;
          return const SizedBox();
        }));
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.text('Continue as guest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan a small step'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      await tester.enterText(find.byType(TextField), 'Synthetic guest draft');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('End guest session'));
      await tester.pumpAndSettle();
    }
    expect(ownerBuilds, 0);
    expect(login.reads, 0);
  });

  testWidgets('read failure and incorrect password keep the owner shell closed',
      (tester) async {
    final login = _ExistingOwner()..failRead = true;
    await tester.pumpWidget(StartupAccessGate(
        login: login,
        ownerBuilder: (hasPassword) =>
            MaterialApp(home: Text('Owner unlocked: $hasPassword'))));
    await tester.tap(find.text('Open my Neura'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not check'), findsOneWidget);
    expect(find.byType(LocalOwnerPasswordScreen), findsNothing);
    login.failRead = false;
    await tester.tap(find.text('Open my Neura'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong fixture');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('That password did not match.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'synthetic owner phrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Owner unlocked: true'), findsOneWidget);
  });

  testWidgets(
      'owner chooses remembered sign-in at setup and can fall back to a password',
      (tester) async {
    final login = _ExistingOwner();
    int admissions = 0;
    const phrase = 'synthetic owner phrase';
    await tester.pumpWidget(MaterialApp(
        home: LocalOwnerPasswordScreen(
            creating: true, login: login, onSuccess: () => admissions++)));
    await tester.enterText(find.byType(TextField).first, phrase);
    await tester.tap(find.text('Save owner password'));
    await tester.pumpAndSettle();
    expect(admissions, 0);
    expect(login.savedPreference, isNull);
    await tester.enterText(find.byType(TextField).last, phrase);
    await tester.tap(find.text('Remember me with Windows Hello'));
    await tester.tap(find.text('Save owner password'));
    await tester.pumpAndSettle();
    expect(login.savedPreference, isTrue);
    expect(admissions, 1);

    bool deviceApproved = false;
    await tester.pumpWidget(MaterialApp(
        home: LocalOwnerPasswordScreen(
            key: const ValueKey('returning owner'),
            creating: false,
            remembered: true,
            login: login,
            verifyDevice: () async => deviceApproved,
            onSuccess: () => admissions++)));
    await tester.tap(find.text('Use Windows Hello'));
    await tester.pumpAndSettle();
    expect(admissions, 1);
    expect(find.text('Enter your owner password to continue.'), findsOneWidget);
    deviceApproved = true;
    await tester.tap(find.text('Use Windows Hello'));
    await tester.pumpAndSettle();
    expect(admissions, 2);
    await tester.tap(find.text('Remember me with Windows Hello'));
    await tester.pumpAndSettle();
    expect(find.text('Use Windows Hello'), findsNothing);
    await tester.enterText(find.byType(TextField), phrase);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(admissions, 3);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'first sign-in carries the guarded owner destination into account creation',
      (tester) async {
    const destination = Text('Synthetic owner destination');
    await tester.pumpWidget(
        const MaterialApp(home: SignInScreen(destination: destination)));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(tester.widget<SignUpScreen>(find.byType(SignUpScreen)).destination,
        same(destination));
    expect(find.text('Synthetic owner destination'), findsNothing);
  });

  for (final screen in <Widget>[
    const SignInScreen(),
    const SignUpScreen(),
    LocalOwnerPasswordScreen(creating: true, onSuccess: () {}),
    LocalOwnerPasswordScreen(creating: false, onSuccess: () {})
  ]) {
    testWidgets(
        'password visibility on ${screen.runtimeType} ${screen is LocalOwnerPasswordScreen ? screen.creating : ""}',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: screen));
      final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Password');
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, 'fictional input');
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      expect(
          tester.widget<TextField>(field).controller!.text, 'fictional input');
      await tester.tap(find.byTooltip('Show password').first);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }
}
