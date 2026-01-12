import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../config/azure_config.dart';

final azureStorageServiceProvider = Provider<AzureStorageService>((ref) {
  final config = ref.read(azureConfigProvider);
  return AzureStorageService(config);
});

class AzureStorageService {
  final AzureConfig config;

  AzureStorageService(this.config);

  // Add your upload/download logic here
  void uploadBlob(List<int> fileBytes, String fileName) {
    try {
      // Placeholder for real Azure upload code
    } catch (e, stackTrace) {
      FirebaseCrashlytics.instance.recordError(e, stackTrace);
    }
  }
}

class AzureSetupScreen extends ConsumerStatefulWidget {
  const AzureSetupScreen({super.key});

  @override
  ConsumerState<AzureSetupScreen> createState() => _AzureSetupScreenState();
}

class _AzureSetupScreenState extends ConsumerState<AzureSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Azure Setup")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter container name:"),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Container Name',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _setupAzure,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text("Setup Azure"),
            ),
          ],
        ),
      ),
    );
  }

  void _setupAzure() async {
    setState(() => _isLoading = true);
    // Add real setup logic here
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.of(context).pop();
    }
  }
}
