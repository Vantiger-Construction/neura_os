import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  AuthGuard({super.key, required this.child});

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> _authenticate() async {
    try {
      final biometricOnly =
          !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
      return await _auth.authenticate(
        localizedReason: 'Please authenticate to continue',
        options: AuthenticationOptions(biometricOnly: biometricOnly),
      );
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authenticate(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == true) {
          return child;
        } else {
          return Scaffold(body: Center(child: Text('Authentication failed')));
        }
      },
    );
  }
}
