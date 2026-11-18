import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/login_password_field.dart';
import '../services/auth_service.dart';
import '../modules/navigation/enhanced_navigation.dart';
import 'verify_email_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen(
      {super.key, this.destination = const EnhancedNavigation()});
  final Widget destination;

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_loading) return;
    final destination = widget.destination;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().signUp(_email.text, _pass.text);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      unawaited(Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(destination: destination))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red)),
            TextField(
                controller: _email,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email
                ],
                decoration: const InputDecoration(labelText: 'Email')),
            LoginPasswordField(
                controller: _pass,
                enabled: !_loading,
                creating: true,
                onSubmitted: (_) => _submit()),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? CircularProgressIndicator()
                    : Text('Create Account')),
          ],
        ),
      ),
    );
  }
}
