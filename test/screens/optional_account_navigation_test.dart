import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:neuro_companion/screens/profile_screen.dart';
import 'package:neuro_companion/screens/sign_in_screen.dart';
import 'package:neuro_companion/screens/verify_email_screen.dart';
import 'package:neuro_companion/services/auth_service.dart';

class _Account extends AuthService {
  bool signedIn = false;
  bool verified = true;
  bool failSignIn = false;
  int signOuts = 0;

  @override
  bool get available => true;
  @override
  User? get user => signedIn && verified
      ? User(
          id: 'synthetic-owner',
          appMetadata: const {},
          userMetadata: const {'display_name': 'Synthetic owner'},
          aud: 'authenticated',
          email: 'fixture@example.invalid',
          createdAt: '2026-11-18T00:00:00Z')
      : null;
  @override
  Future<void> signIn(String email, String pass) async {
    if (failSignIn) throw StateError('Synthetic sign-in failure');
    signedIn = true;
  }

  @override
  Future<void> signUp(String email, String pass) async {
    signedIn = true;
    verified = false;
  }

  @override
  Future<bool> isEmailVerified() async => signedIn && verified;
  @override
  Future<void> signOut() async {
    signedIn = false;
    signOuts++;
  }
}

Future<void> _openProfile(WidgetTester tester, _Account auth) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                  body: Column(children: [
                const Text('Synthetic local workspace'),
                TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ProfileScreen(auth: auth))),
                    child: const Text('Open profile')),
              ])))));
  await tester.tap(find.text('Open profile'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('optional sign-in and sign-out preserve the local navigation',
      (tester) async {
    final auth = _Account();
    await _openProfile(tester, auth);
    expect(find.byType(SignInScreen), findsNothing);
    await tester.tap(find.text('Sign in to cloud account (optional)'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'fixture@example.invalid');
    await tester.enterText(find.byType(TextField).last, 'synthetic passphrase');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.text('fixture@example.invalid'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out of cloud account'));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.text('Sign in to cloud account (optional)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic local workspace'), findsOneWidget);
  });

  testWidgets('account creation returns only after explicit email verification',
      (tester) async {
    final auth = _Account();
    await _openProfile(tester, auth);
    await tester.tap(find.text('Sign in to cloud account (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'fixture@example.invalid');
    await tester.enterText(find.byType(TextField).last, 'synthetic passphrase');
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    auth.verified = true;
    await tester.tap(find.text('I have verified'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic local workspace'), findsOneWidget);
  });

  testWidgets(
      'a returning unverified account refreshes Profile after verification',
      (tester) async {
    final auth = _Account()..verified = false;
    await _openProfile(tester, auth);
    await tester.tap(find.text('Sign in to cloud account (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    auth.verified = true;
    await tester.tap(find.text('I have verified'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Synthetic owner');
  });

  testWidgets(
      'a failed or cancelled account sign-in leaves local use available',
      (tester) async {
    final auth = _Account()..failSignIn = true;
    await _openProfile(tester, auth);
    await tester.tap(find.text('Sign in to cloud account (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Synthetic sign-in failure'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic local workspace'), findsOneWidget);
  });
}
