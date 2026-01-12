import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'sign_up_screen.dart';
import 'reset_password_screen.dart';
import 'verify_email_screen.dart';

class SignInScreen extends StatefulWidget {
  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService().signIn(_email.text, _pass.text);
      if (!(await AuthService().isEmailVerified())) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VerifyEmailScreen()));
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _googleSignIn() async {
    await AuthService().signInWithGoogle();
    if (!(await AuthService().isEmailVerified())) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VerifyEmailScreen()));
    }
  }

  Future<void> _appleSignIn() async {
    await AuthService().signInWithApple();
    if (!(await AuthService().isEmailVerified())) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VerifyEmailScreen()));
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null) Text(_error!, style: TextStyle(color: Colors.red)),
            TextField(controller: _email, decoration: InputDecoration(labelText: 'Email')),
            TextField(controller: _pass, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loading ? null : _submit, child: _loading ? CircularProgressIndicator() : Text('Sign In')),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: _googleSignIn, icon: Icon(Icons.login), label: Text('Sign in with Google')),
            ElevatedButton.icon(onPressed: _appleSignIn, icon: Icon(Icons.apple), label: Text('Sign in with Apple')),
            TextButton(onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => SignUpScreen())), child: const Text('Create account')),
            TextButton(onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ResetPasswordScreen())), child: const Text('Forgot password?')),
          ],
        ),
      ),
    );
  }
}
