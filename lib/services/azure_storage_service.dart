import 'package:flutter/material.dart';

import '../config/azure_config.dart';
import '../modules/core/app_log.dart';

/// Optional Azure Blob helper.
///
/// This is intentionally a lightweight stub so your build doesn't depend on
/// any Azure packages unless you choose to add them.
class AzureStorageService {
  final AzureConfig config;

  AzureStorageService(this.config);

  Future<void> uploadBlob({required List<int> bytes, required String fileName}) async {
    // TODO: implement with your chosen Azure package.
    await AppLog.instance.info('Azure stub: upload requested for $fileName (bytes=${bytes.length}).');
  }
}

class AzureSetupScreen extends StatefulWidget {
  const AzureSetupScreen({super.key});

  @override
  State<AzureSetupScreen> createState() => _AzureSetupScreenState();
}

class _AzureSetupScreenState extends State<AzureSetupScreen> {
  final TextEditingController _accountName = TextEditingController();
  final TextEditingController _accountKey = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _accountName.dispose();
    _accountKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Azure Setup (Optional)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Account name'),
            const SizedBox(height: 8),
            TextField(
              controller: _accountName,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'myaccount'),
            ),
            const SizedBox(height: 16),
            const Text('Account key'),
            const SizedBox(height: 8),
            TextField(
              controller: _accountKey,
              obscureText: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '••••••••'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
            const SizedBox(height: 8),
            Text(
              'Heads up: this screen only stores keys in-memory in this stub build. '
              'Wire it into secure storage when you enable Azure uploads.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    await AppLog.instance.info('Azure stub: config entered (name=${_accountName.text.isNotEmpty}).');
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.of(context).pop(const AzureConfig(accountName: '', accountKey: ''));
  }
}
