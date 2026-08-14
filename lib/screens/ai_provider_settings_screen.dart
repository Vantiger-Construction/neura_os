import 'package:flutter/material.dart';

import '../services/neura_provider_credentials.dart';
import '../services/neura_swarm_service.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({super.key});

  @override
  State<AiProviderSettingsScreen> createState() =>
      _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState
    extends State<AiProviderSettingsScreen> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = NeuraProviderCredentials.validate(_keyController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _saving = true);
    try {
      await NeuraProviderCredentials.instance.save(_keyController.text);
      try {
        await NeuraSwarmService.instance.init(
          NeuraProviderCredentials.instance.apiKey,
        );
      } catch (_) {
        // The key is safely stored. The native swarm will receive it on the
        // next app start if its library is temporarily unavailable now.
      }
      _keyController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI provider key saved securely.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The key could not be saved securely.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove AI provider key?'),
        content: const Text(
          'Cloud replies will stop until another key is saved. '
          'Neura\'s local fallback will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NeuraProviderCredentials.instance.clear();
    try {
      await NeuraSwarmService.instance.clearCredential();
    } catch (_) {
      // Secure storage is authoritative; a restart also clears native memory.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI provider key removed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credentials = NeuraProviderCredentials.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Provider')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: credentials.configured,
            builder: (context, configured, _) => Card(
              child: ListTile(
                leading: Icon(
                  configured ? Icons.verified_user_outlined : Icons.cloud_off,
                ),
                title: Text(configured ? 'Connected securely' : 'Not configured'),
                subtitle: Text(
                  configured
                      ? 'The key is stored by your operating system and is never displayed.'
                      : 'Neura will use its local fallback until a key is saved.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Anthropic API key',
              hintText: 'sk-ant-…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show' : 'Hide',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            onSubmitted: _saving ? null : (_) => _save(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline),
            label: const Text('Save securely'),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: credentials.configured,
            builder: (context, configured, _) => OutlinedButton.icon(
              onPressed: configured && !_saving ? _remove : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove saved key'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Security note: do not paste this key into chat, source files, '
            'screenshots, or build scripts. New release builds should omit '
            'ANTHROPIC_API_KEY from --dart-define.',
          ),
        ],
      ),
    );
  }
}
