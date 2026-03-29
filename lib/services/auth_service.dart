import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static Stream<User?> get onAuthStateChanged => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String pass) =>
      _auth.signInWithEmailAndPassword(email: email, password: pass);

  Future<void> signUp(String email, String pass) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: pass);
    await sendEmailVerification();
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;
    await user?.reload();
    return user?.emailVerified ?? false;
  }

  /// Google Sign-In
  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return; // User cancelled
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken, accessToken: googleAuth.accessToken);
    await _auth.signInWithCredential(credential);
  }

  /// Apple Sign-In
  Future<void> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName
      ],
    );
    final oAuthProvider = OAuthProvider("apple.com");
    final authCredential = oAuthProvider.credential(
      idToken: credential.identityToken,
      accessToken: credential.authorizationCode,
    );
    await _auth.signInWithCredential(authCredential);
  }
}
