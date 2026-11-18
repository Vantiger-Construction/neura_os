import 'dart:async';

import 'package:flutter/material.dart';
import '../modules/navigation/enhanced_navigation.dart';
import '../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.destination = const EnhancedNavigation(),
    this.onAuthenticated,
    this.auth,
  });
  final Widget destination;
  final VoidCallback? onAuthenticated;
  final AuthService? auth;

  @override
  _VerifyEmailScreenState createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _emailSent = false;
  bool _completed = false;
  AuthService get _auth => widget.auth ?? AuthService();

  @override
  void initState() {
    super.initState();
    _checkVerified();
  }

  Future<void> _checkVerified() async {
    final verified = await _auth.isEmailVerified();
    if (!mounted || _completed) return;
    if (verified) {
      _completed = true;
      final onAuthenticated = widget.onAuthenticated;
      if (onAuthenticated != null) {
        onAuthenticated();
        return;
      }
      final destination = widget.destination;
      unawaited(Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      ));
    }
  }

  Future<void> _resend() async {
    await _auth.sendEmailVerification();
    if (mounted) setState(() => _emailSent = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Verify Email')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text('A verification email has been sent to your address.'),
            if (_emailSent)
              Text('Email resent! Check your inbox.',
                  style: TextStyle(color: Colors.green)),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _resend, child: Text('Resend Email')),
            SizedBox(height: 16),
            ElevatedButton(
                onPressed: _checkVerified, child: Text('I have verified')),
          ],
        ),
      ),
    );
  }
}
