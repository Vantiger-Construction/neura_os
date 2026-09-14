import 'package:flutter/material.dart';

import '../services/neura_model_credentials.dart';
import '../services/neura_model_types.dart';
import '../services/neura_provider_credentials.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({super.key});

  @override
  State<AiProviderSettingsScreen> createState() =>
      _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState extends State<AiProviderSettingsScreen> {
  final _keyController = TextEditingController();
  NeuraModelProvider _provider = NeuraModelProvider.openAi;
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error =
        NeuraModelCredentials.validate(_provider, _keyController.text);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _saving = true);
    try {
      await NeuraModelCredentials.instance.save(
        _provider,
        _keyController.text,
      );
      // Keep the existing Anthropic chat path synchronized until the
      // provider-neutral router becomes its authoritative transport.
      if (_provider == NeuraModelProvider.anthropic) {
        await NeuraProviderCredentials.instance.save(_keyController.text);
      }
      _keyController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_provider.label} key saved securely.')),
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

  Future<void> _remove(NeuraModelProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${provider.label} key?'),
        content: const Text(
          'Cloud requests to this provider will stop. The secret cannot be '
          'recovered after verified removal.',
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

    try {
      await NeuraModelCredentials.instance.clear(provider);
      if (provider == NeuraModelProvider.anthropic &&
          NeuraProviderCredentials.instance.hasKey) {
        await NeuraProviderCredentials.instance.clear();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Key removal could not be verified. Close Neura and try again.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${provider.label} key removed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credentials = NeuraModelCredentials.instance;
    final hint = _provider == NeuraModelProvider.openAi ? 'sk-…' : 'sk-ant-…';

    return Scaffold(
      appBar: AppBar(title: const Text('AI Providers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Approval required every time'),
              subtitle: Text(
                'Neura previews each cloud request before sending it. '
                'Safe Mode blocks all cloud providers.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<NeuraModelProvider>(
            segments: NeuraModelProvider.values
                .map(
                  (provider) => ButtonSegment(
                    value: provider,
                    label: Text(provider.label),
                  ),
                )
                .toList(),
            selected: {_provider},
            onSelectionChanged: _saving
                ? null
                : (selection) => setState(() {
                      _provider = selection.single;
                      _keyController.clear();
                    }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '${_provider.label} API key',
              hintText: hint,
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
            label: Text('Save ${_provider.label} key securely'),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Set<NeuraModelProvider>>(
            valueListenable: credentials.configured,
            builder: (context, configured, _) => Column(
              children: [
                for (final provider in NeuraModelProvider.values)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        configured.contains(provider)
                            ? Icons.verified_user_outlined
                            : Icons.cloud_off,
                      ),
                      title: Text(provider.label),
                      subtitle: Text(
                        configured.contains(provider)
                            ? 'Stored by the operating system'
                            : 'Not configured',
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove ${provider.label} key',
                        onPressed: configured.contains(provider) && !_saving
                            ? () => _remove(provider)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'OpenAI is tried first. Anthropic is an optional fallback and '
            'requires a separate approval. Never paste API keys into chat, '
            'source files, screenshots, or build scripts.',
          ),
        ],
      ),
    );
  }
}
