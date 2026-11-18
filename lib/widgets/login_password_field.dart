import 'package:flutter/material.dart';

class LoginPasswordField extends StatefulWidget {
  const LoginPasswordField({
    super.key,
    required this.controller,
    this.creating = false,
    this.label = 'Password',
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool creating;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<LoginPasswordField> createState() => _LoginPasswordFieldState();
}

class _LoginPasswordFieldState extends State<LoginPasswordField>
    with WidgetsBindingObserver {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_visible && state != AppLifecycleState.resumed) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: !_visible,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        autofillHints: [
          widget.creating ? AutofillHints.newPassword : AutofillHints.password
        ],
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: _visible ? 'Hide password' : 'Show password',
            icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
            onPressed: widget.enabled
                ? () => setState(() => _visible = !_visible)
                : null,
          ),
        ),
      );
}
