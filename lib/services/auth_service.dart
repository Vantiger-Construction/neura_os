import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AuthService {
  static SupabaseClient? _clientCache;

  static SupabaseClient get _client =>
      _clientCache ??= Supabase.instance.client;

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

  /// Clears only this device's live Supabase session during a local-data
  /// wipe. Other devices remain signed in. Local invalidation happens before
  /// the SDK's best-effort server notification, so an offline endpoint cannot
  /// leave the wipe waiting forever.
  Future<void> clearLocalSessionForDataWipe() async {
    if (!SupabaseConfig.isConfigured) return;
    // A Safe Mode boot deliberately never initializes Supabase. Its persisted
    // session is removed by the verified preferences wipe below; touching the
    // singleton here would itself throw. A normal boot always reaches
    // [currentUser] and therefore caches the live client before navigation.
    final client = _clientCache;
    if (client == null) return;
    final auth = client.auth;
    try {
      await auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // The server notification may fail offline. What matters for a local
      // wipe is that the client discarded its in-memory session; persistent
      // SDK storage is removed by signOut and the verified prefs clear.
    }
    if (auth.currentSession != null) {
      throw StateError('The local sign-in session could not be removed.');
    }
  }

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
