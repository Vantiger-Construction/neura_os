import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  _VerifyEmailScreenState createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _emailSent = false;

  @override
  void initState() {
    super.initState();
    _checkVerified();
  }

  Future<void> _checkVerified() async {
    final verified = await AuthService().isEmailVerified();
    if (verified) {
      Navigator.pushReplacementNamed(context, '/'); // main nav
    }
  }

  Future<void> _resend() async {
    await AuthService().sendEmailVerification();
    setState(() => _emailSent = true);
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
