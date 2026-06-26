import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static Stream<User?> get onAuthStateChanged =>
      _client.auth.onAuthStateChange.map((e) => e.session?.user);

  Future<void> signIn(String email, String pass) =>
      _client.auth.signInWithPassword(email: email, password: pass);

  Future<void> signUp(String email, String pass) =>
      _client.auth.signUp(email: email, password: pass);

  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email);

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendEmailVerification() async {
    final email = _client.auth.currentUser?.email;
    if (email != null) {
      await _client.auth.resend(type: OtpType.signup, email: email);
    }
  }

  Future<bool> isEmailVerified() async {
    try {
      await _client.auth.refreshSession();
    } catch (_) {}
    return _client.auth.currentUser?.emailConfirmedAt != null;
  }

  // OAuth — wired post-beta
  Future<void> signInWithGoogle() async =>
      throw UnimplementedError('Google sign-in coming post-beta.');

  Future<void> signInWithApple() async =>
      throw UnimplementedError('Apple sign-in coming post-beta.');
}
