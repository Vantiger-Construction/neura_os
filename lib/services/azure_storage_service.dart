import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as cry;
import 'package:flutter/material.dart';

import '../config/azure_config.dart';
import '../modules/core/app_log.dart';

/// Azure Blob Storage helper using the REST API with Shared Key authentication.
///
/// Requires a valid [AzureConfig] with accountName and accountKey (base-64).
/// Container must already exist in your storage account.
class AzureStorageService {
  final AzureConfig config;

  /// The blob container to upload into. Override as needed.
  final String container;

  AzureStorageService(this.config, {this.container = 'neura-uploads'});

  /// Uploads [bytes] as a block blob named [fileName] to the configured container.
  ///
  /// Uses the Azure Blob Storage REST API PUT endpoint with Shared Key auth.
  /// No-ops silently if [config.isConfigured] is false.
  Future<void> uploadBlob({
    required List<int> bytes,
    required String fileName,
    String contentType = 'application/octet-stream',
  }) async {
    if (!config.isConfigured) {
      await AppLog.instance.info(
          'Azure: skipping upload of $fileName — account not configured.');
      return;
    }

    final data = Uint8List.fromList(bytes);
    final now = _httpDate();
    final contentLength = data.length.toString();

    // Build the string-to-sign for Shared Key Lite authentication.
    // https://learn.microsoft.com/azure/storage/common/storage-rest-api-auth
    final canonicalizedResource =
        '/${config.accountName}/$container/$fileName';
    final stringToSign = [
      'PUT',        // HTTP method
      '',           // Content-Encoding
      '',           // Content-Language
      contentLength,
      '',           // Content-MD5
      contentType,
      '',           // Date (use x-ms-date instead)
      '',           // If-Modified-Since
      '',           // If-Match
      '',           // If-None-Match
      '',           // If-Unmodified-Since
      '',           // Range
      'x-ms-blob-type:BlockBlob\nx-ms-date:$now\nx-ms-version:2020-10-02',
      canonicalizedResource,
    ].join('\n');

    final keyBytes = base64.decode(config.accountKey);
    final mac = await cry.Hmac.sha256().calculateMac(
      utf8.encode(stringToSign),
      secretKey: cry.SecretKey(keyBytes),
    );
    final sig = base64.encode(mac.bytes);
    final auth =
        'SharedKey ${config.accountName}:$sig';

    final uri = Uri.https(
      '${config.accountName}.blob.core.windows.net',
      '/$container/$fileName',
    );

    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      request.headers
        ..set('x-ms-date', now)
        ..set('x-ms-version', '2020-10-02')
        ..set('x-ms-blob-type', 'BlockBlob')
        ..set(HttpHeaders.contentTypeHeader, contentType)
        ..set(HttpHeaders.contentLengthHeader, contentLength)
        ..set(HttpHeaders.authorizationHeader, auth);
      request.add(data);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == 201) {
        await AppLog.instance
            .info('Azure: uploaded $fileName (${data.length} bytes).');
      } else {
        await AppLog.instance.warn(
            'Azure: upload of $fileName returned ${response.statusCode}.');
      }
    } catch (e) {
      await AppLog.instance.warn('Azure: upload error for $fileName — $e');
    } finally {
      client.close();
    }
  }

  /// RFC 1123 date string required by Azure REST headers.
  static String _httpDate() {
    final d = DateTime.now().toUtc();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]}, $dd ${months[d.month]} ${d.year} $hh:$mm:$ss GMT';
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
