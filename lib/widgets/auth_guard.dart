import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

/// Gates [child] behind device authentication (biometrics or PIN/password).
///
/// Re-checked once per widget lifetime — the authenticate call is cached in
/// [initState], not re-triggered by every rebuild (a bare
/// `FutureBuilder(future: _authenticate())` in `build()` would call it on
/// every rebuild, e.g. every theme or MediaQuery change).
class AuthGuard extends StatefulWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  final LocalAuthentication _auth = LocalAuthentication();
  late Future<bool> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = _authenticate();
  }

  Future<bool> _authenticate() async {
    try {
      final biometricOnly =
          !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
      return await _auth.authenticate(
        localizedReason: 'Please authenticate to open Neura',
        options: AuthenticationOptions(biometricOnly: biometricOnly),
      );
    } catch (e) {
      return false;
    }
  }

  void _retry() {
    setState(() {
      _authFuture = _authenticate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == true) {
          return widget.child;
        }
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                const Text('Authentication failed'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _retry, child: const Text('Try again')),
              ],
            ),
          ),
        );
      },
    );
  }
}
