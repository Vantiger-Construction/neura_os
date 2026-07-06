import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'legacy_pdf_export_service.dart';
import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';

class LegacyDeliveryService {
  LegacyDeliveryService._();

  static final LegacyDeliveryService instance = LegacyDeliveryService._();

  Future<XFile> createDeliveryPacket({
    required LegacyCapsule capsule,
    required String preferFormat,
    bool decryptIfPossible = false,
    String? passphraseOverride,
    String? recipientName,
    String? deliveryNote,
    BuildContext? context,
  }) async {
    String format = preferFormat.toLowerCase().trim();
    if (format != 'zip' && format != 'pdf' && format != 'json') {
      format = 'zip';
    }

    String? pass = passphraseOverride;
    if (decryptIfPossible && capsule.isEncrypted && (pass == null || pass.trim().isEmpty) && context != null) {
      pass = await _promptPassphrase(
        context,
        title: 'Passphrase to decrypt “${capsule.title.isEmpty ? 'capsule' : capsule.title}”',
      );
      if (pass == null || pass.trim().isEmpty) {
        // User cancelled. Fall back to encrypted export.
        decryptIfPossible = false;
        pass = null;
      }
    }

    if (format == 'pdf' && capsule.isEncrypted && !decryptIfPossible) {
      format = 'zip';
    }

    if (format == 'pdf') {
      final f = await LegacyPdfExportService.instance.exportCapsulePdf(
        capsule: capsule,
        passphrase: pass,
        decryptIfPossible: decryptIfPossible,
        recipientName: recipientName,
        deliveryNote: deliveryNote,
      );
      return XFile(f.path);
    }

    if (format == 'json') {
      final f = await LegacyVaultService.instance.exportCapsule(
        capsule.id,
        passphrase: pass,
        decrypted: decryptIfPossible,
      );
      return XFile(f.path);
    }

    // zip
    final f = await LegacyVaultService.instance.exportCapsuleZip(
      capsule.id,
      passphrase: pass,
      decrypted: decryptIfPossible,
    );
    return XFile(f.path);
  }

  Future<void> shareFiles({required List<String> filePaths, String? text}) async {
    final files = filePaths.map((p) => XFile(p)).toList();
    await Share.shareXFiles(files, text: text);
  }

  Future<String?> _promptPassphrase(BuildContext context, {required String title}) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Continue')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}
