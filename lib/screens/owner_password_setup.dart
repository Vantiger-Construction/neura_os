import 'package:flutter/material.dart';

import '../services/local_owner_login.dart';
import '../startup/neura_prefs_cache.dart';
import 'local_owner_password_screen.dart';

/// Optional local password setup, offered after any enabled device lock.
class OwnerPasswordSetup extends StatefulWidget {
  const OwnerPasswordSetup({super.key, required this.child});
  final Widget child;

  @override
  State<OwnerPasswordSetup> createState() => _OwnerPasswordSetupState();
}

class _OwnerPasswordSetupState extends State<OwnerPasswordSetup> {
  bool _done = false;

  Future<void> _continue() async {
    try {
      await NeuraPrefsCache.prefs
          .setBool(LocalOwnerLogin.setupDismissedKey, true);
    } catch (_) {
      // This is only a prompt preference; the secure record governs access.
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) => _done
      ? widget.child
      : LocalOwnerPasswordScreen(
          creating: true, onSuccess: _continue, onSkip: _continue);
}
