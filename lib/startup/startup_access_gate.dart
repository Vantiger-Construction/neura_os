import 'package:flutter/material.dart';

import '../modules/support/wellbeing_session_screen.dart';
import '../screens/local_owner_password_screen.dart';
import '../services/local_owner_login.dart';
import '../theme/app_theme.dart';

/// The production shell, its Navigator, profiles and startup services are
/// mounted only after the owner path is selected and any saved lock opens.
class StartupAccessGate extends StatefulWidget {
  const StartupAccessGate({super.key, required this.ownerBuilder, this.login});
  final Widget Function(bool hasPassword) ownerBuilder;
  final LocalOwnerLogin? login;

  @override
  State<StartupAccessGate> createState() => _StartupAccessGateState();
}

class _StartupAccessGateState extends State<StartupAccessGate> {
  bool? _ownerHasPassword;
  bool _loading = false;
  String? _error;
  // Recovery can remount this widget after production services have run.
  // A new guest session must always start from a fresh process.
  static bool _ownerStarted = false;

  void _openOwner(bool hasPassword) => setState(() {
        _ownerStarted = true;
        _ownerHasPassword = hasPassword;
      });

  Future<void> _owner(BuildContext context) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final remembered =
          await (widget.login ?? LocalOwnerLogin.instance).remembered();
      if (!context.mounted) return;
      if (remembered == null) {
        _openOwner(false);
        return;
      }
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (context) => LocalOwnerPasswordScreen(
              creating: false,
              remembered: remembered,
              login: widget.login,
              onSuccess: () => Navigator.of(context).pop(true))));
      if (mounted && ok == true) _openOwner(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not check the owner login. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = _ownerHasPassword;
    if (hasPassword != null) return widget.ownerBuilder(hasPassword);
    return MaterialApp(
      title: 'Neura',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Builder(
          builder: (context) => Scaffold(
                  body: SafeArea(
                      child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text('Welcome to Neura',
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 24),
                        FilledButton(
                            onPressed: _loading ? null : () => _owner(context),
                            child: const Text('Open my Neura')),
                        if (!_ownerStarted)
                          OutlinedButton(
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => const _GuestHome())),
                              child: const Text('Continue as guest')),
                        if (_error != null) Text(_error!),
                      ]),
                ),
              )))),
    );
  }
}

class _GuestHome extends StatelessWidget {
  const _GuestHome();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Guest session')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              'Try a small step or a gentle reminder. Your work disappears when you leave.'),
          ListTile(
              title: const Text('Plan a small step'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const WellbeingSessionScreen()))),
          ListTile(
              title: const Text('Try a gentle reminder'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      const WellbeingSessionScreen(reminder: true)))),
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('End guest session')),
        ])),
      );
}
