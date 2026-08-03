import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services/app_lock_prefs.dart';

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
  bool _bypassed = false;

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

  /// Escape hatch for the case where device auth itself is broken (Windows
  /// Hello disabled/uninstalled, biometric hardware failure, forgotten PIN,
  /// etc.) — without this, the "Require device lock" toggle lives inside the
  /// very screen this widget gates, so a persistent auth failure would
  /// permanently lock the user out with no in-app way back to turn it off.
  Future<void> _disableLockAndContinue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off device lock?'),
        content: const Text(
          "Neura can't verify your device authentication right now. "
          'Turning off device lock removes this screen so you can get back '
          'into Neura — anyone with access to this device will be able to '
          'open it without authenticating until you turn it back on in '
          'Settings > Privacy & Safety.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn off and continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLockPrefsController.instance.setEnabled(false);
    if (!mounted) return;
    setState(() => _bypassed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_bypassed) return widget.child;
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
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _disableLockAndContinue,
                  child: const Text('Turn off device lock'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
