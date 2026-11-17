import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../services/local_owner_login.dart';
import '../widgets/login_password_field.dart';

class LocalOwnerPasswordScreen extends StatefulWidget {
  const LocalOwnerPasswordScreen({
    super.key,
    required this.creating,
    required this.onSuccess,
    this.remembered = false,
    this.removing = false,
    this.onSkip,
    this.login,
    this.verifyDevice,
  });
  final bool creating;
  final bool remembered;
  final bool removing;
  final VoidCallback onSuccess;
  final VoidCallback? onSkip;
  final LocalOwnerLogin? login;
  final Future<bool> Function()? verifyDevice;

  @override
  State<LocalOwnerPasswordScreen> createState() =>
      _LocalOwnerPasswordScreenState();
}

class _LocalOwnerPasswordScreenState extends State<LocalOwnerPasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late bool _remember = widget.remembered;
  bool _busy = false;
  String? _message;
  bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  LocalOwnerLogin get _login => widget.login ?? LocalOwnerLogin.instance;

  Future<bool> _authenticateDevice() =>
      widget.verifyDevice?.call() ??
      LocalAuthentication()
          .authenticate(localizedReason: 'Unlock your Neura owner workspace');

  Future<void> _submit({bool useSaved = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (useSaved) {
        if (!await _login.unlockRemembered(_authenticateDevice)) {
          if (mounted) {
            setState(() => _message = 'Enter your owner password to continue.');
          }
          return;
        }
      } else {
        final password = _password.text;
        if (widget.creating) {
          if (password.trim().length < 12 || password != _confirmation.text) {
            setState(() => _message =
                'Use at least 12 characters and enter the same password twice.');
            return;
          }
          await _login.create(password, remember: _remember);
        } else if (!(widget.removing
            ? await _login.remove(password)
            : await _login.unlock(password, remember: _remember))) {
          if (mounted) {
            setState(() => _message = 'That password did not match.');
          }
          return;
        }
      }
      if (!mounted) return;
      TextInput.finishAutofillContext(
          shouldSave: !useSaved && !widget.removing);
      _password.clear();
      _confirmation.clear();
      widget.onSuccess();
    } catch (_) {
      if (mounted) {
        setState(() => _message = useSaved
            ? 'Windows Hello is unavailable. Enter your owner password.'
            : 'Could not access your owner login. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.creating
                  ? 'Set up owner password'
                  : widget.removing
                      ? 'Remove owner password'
                      : 'Owner login')),
          body: SafeArea(
              child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(widget.creating
                        ? (_windows
                            ? 'Choose a phrase of at least 12 characters. Enable Windows Hello below to sign in without typing it next time.'
                            : 'Choose a phrase of at least 12 characters. Your device’s password manager can offer to save it.')
                        : widget.removing
                            ? 'Enter your current password to turn off the Neura owner password on this device.'
                            : 'Enter your password to open your personal workspace.'),
                    if (_windows &&
                        widget.remembered &&
                        _remember &&
                        !widget.removing)
                      FilledButton.icon(
                          onPressed:
                              _busy ? null : () => _submit(useSaved: true),
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Use Windows Hello')),
                    LoginPasswordField(
                        controller: _password,
                        creating: widget.creating,
                        enabled: !_busy,
                        onSubmitted: widget.creating ? null : (_) => _submit()),
                    if (widget.creating)
                      LoginPasswordField(
                          controller: _confirmation,
                          creating: true,
                          label: 'Confirm password',
                          enabled: !_busy,
                          onSubmitted: (_) => _submit()),
                    if (_windows && !widget.removing)
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _remember,
                          title: const Text('Remember me with Windows Hello'),
                          onChanged: _busy
                              ? null
                              : (value) =>
                                  setState(() => _remember = value == true)),
                    if (_message != null)
                      Text(_message!, semanticsLabel: _message),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(widget.creating
                            ? 'Save owner password'
                            : widget.removing
                                ? 'Remove password'
                                : 'Unlock')),
                    if (widget.onSkip != null)
                      const Text(
                          'Skipping lets anyone using this device open the owner workspace unless another device lock is enabled.'),
                    if (widget.onSkip != null)
                      TextButton(
                          onPressed: _busy ? null : widget.onSkip,
                          child:
                              const Text('Continue without an owner password')),
                  ]),
            )),
          )),
        ),
      );
}
