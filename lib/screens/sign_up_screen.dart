import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'verify_email_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().signUp(_email.text, _pass.text);
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => VerifyEmailScreen()));
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red)),
            TextField(
                controller: _email,
                decoration: InputDecoration(labelText: 'Email')),
            TextField(
                controller: _pass,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true),
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
