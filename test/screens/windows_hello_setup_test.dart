import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/screens/local_owner_password_screen.dart';
import 'package:neuro_companion/services/local_owner_login.dart';

class _OwnerLogin extends Fake implements LocalOwnerLogin {
  int saves = 0;
  bool? remembered;

  @override
  Future<void> create(String password, {required bool remember}) async {
    saves++;
    remembered = remember;
  }

  @override
  Future<bool> unlock(String password, {required bool remember}) async {
    remembered = remember;
    return password == 'synthetic owner passphrase';
  }
}

void main() {
  testWidgets('Windows Hello setup opens settings and requires OS approval',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final login = _OwnerLogin();
    var supported = false;
    var approved = false;
    var settingsOpened = 0;
    var approvals = 0;
    var admissions = 0;
    await tester.pumpWidget(MaterialApp(
        home: LocalOwnerPasswordScreen(
            creating: true,
            login: login,
            deviceSupported: () async => supported,
            openDeviceSettings: () async {
              settingsOpened++;
              return true;
            },
            verifyDevice: () async {
              approvals++;
              return approved;
            },
            onSuccess: () => admissions++)));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull);
    await tester.tap(find.text('Set up Windows Hello'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(approvals, 0);
    expect(login.saves, 0);
    supported = true;
    await tester.tap(find.text('Check Windows Hello again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remember me with Windows Hello'));
    await tester.enterText(
        find.byType(TextField).first, 'synthetic owner passphrase');
    await tester.enterText(
        find.byType(TextField).last, 'synthetic owner passphrase');
    await tester.tap(find.text('Save owner password'));
    await tester.pumpAndSettle();
    expect(approvals, 1);
    expect(login.saves, 0);
    expect(admissions, 0);
    expect(
        find.textContaining('Windows Hello was not completed'), findsOneWidget);
    approved = true;
    await tester.tap(find.text('Save owner password'));
    await tester.pumpAndSettle();
    expect(login.saves, 1);
    expect(login.remembered, isTrue);
    expect(admissions, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('an unavailable Windows Hello still allows password fallback',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final login = _OwnerLogin();
    var admissions = 0;
    await tester.pumpWidget(MaterialApp(
        home: LocalOwnerPasswordScreen(
            creating: false,
            remembered: true,
            login: login,
            deviceSupported: () async => false,
            openDeviceSettings: () async => false,
            onSuccess: () => admissions++)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up Windows Hello'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Open Windows Settings > Accounts'),
        findsOneWidget);
    await tester.tap(find.text('Remember me with Windows Hello'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'synthetic owner passphrase');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(admissions, 1);
    expect(login.remembered, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
