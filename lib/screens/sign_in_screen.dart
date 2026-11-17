import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/login_password_field.dart';
import '../modules/navigation/enhanced_navigation.dart';
import '../services/auth_service.dart';
import 'sign_up_screen.dart';
import 'reset_password_screen.dart';
import 'verify_email_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().signIn(_email.text, _pass.text);
      if (!mounted) return;
      final verified = await AuthService().isEmailVerified();
      if (!mounted) return;
      TextInput.finishAutofillContext();
      if (verified) {
        unawaited(Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EnhancedNavigation()),
          (route) => false,
        ));
      } else {
        unawaited(Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => VerifyEmailScreen())));
      }
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
      appBar: AppBar(title: const Text('Sign In')),
      body: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
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
                onSubmitted: (_) => _submit()),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Sign In')),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.push(
                        ctx, MaterialPageRoute(builder: (_) => SignUpScreen())),
                child: const Text('Create account')),
            TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.push(
                        ctx,
                        MaterialPageRoute(
                            builder: (_) => ResetPasswordScreen())),
                child: const Text('Forgot password?')),
          ],
        ),
      ),
    );
  }
}
