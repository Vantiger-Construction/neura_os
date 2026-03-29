import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  AuthGuard({super.key, required this.child});

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> _authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Please authenticate to continue',
        options: const AuthenticationOptions(biometricOnly: true),
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
