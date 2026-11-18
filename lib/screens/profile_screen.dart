import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'sign_in_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.auth});
  final AuthService? auth;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameCtrl;
  bool _updating = false;
  String? _error;
  AuthService get _auth => widget.auth ?? AuthService();

  @override
  void initState() {
    super.initState();
    final meta = _auth.user?.userMetadata;
    _nameCtrl = TextEditingController(
      text: meta?['display_name'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await _auth.updateDisplayName(_nameCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _signIn() async {
    final origin = ModalRoute.of(context);
    if (origin == null) return;
    final navigator = Navigator.of(context);
    await navigator.push<void>(MaterialPageRoute(
        builder: (_) => SignInScreen(
            auth: widget.auth,
            onAuthenticated: () {
              if (!mounted || !origin.isActive) return;
              navigator.popUntil((route) => identical(route, origin));
              _refreshAccount();
            })));
    if (!mounted) return;
    _refreshAccount();
  }

  void _refreshAccount() {
    setState(() {
      _nameCtrl.text =
          _auth.user?.userMetadata?['display_name'] as String? ?? '';
      _error = null;
    });
  }

  Future<void> _signOut() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await _auth.signOut();
      if (mounted) setState(() => _nameCtrl.clear());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not sign out. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.user;
    final initial =
        user?.email?.isNotEmpty == true ? user!.email![0].toUpperCase() : '?';
    final cloudAvailable = _auth.available;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out of cloud account',
            onPressed:
                cloudAvailable && user != null && !_updating ? _signOut : null,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user == null) ...[
              const Text(
                  'You can use Neura on this device without a cloud account.'),
              const SizedBox(height: 12),
              if (cloudAvailable)
                FilledButton(
                    onPressed: _signIn,
                    child: const Text('Sign in to cloud account (optional)')),
              const SizedBox(height: 16),
            ],
            CircleAvatar(
              radius: 40,
              child: Text(initial, style: const TextStyle(fontSize: 32)),
            ),
            const SizedBox(height: 12),
            Text(
              user?.email ??
                  (cloudAvailable ? '' : 'Cloud profile unavailable'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            TextField(
              controller: _nameCtrl,
              enabled: cloudAvailable && user != null,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  _updating || !cloudAvailable || user == null ? null : _save,
              child: _updating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Profile'),
            ),
          ],
        ),
      ),
    );
  }
}
