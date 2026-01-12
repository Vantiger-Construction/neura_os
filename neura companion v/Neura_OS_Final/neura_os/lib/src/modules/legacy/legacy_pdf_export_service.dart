import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';

class LegacyPdfExportService {
  LegacyPdfExportService._();

  static final LegacyPdfExportService instance = LegacyPdfExportService._();

  Future<File> exportCapsulePdf({
    required LegacyCapsule capsule,
    String? passphrase,
    bool decryptIfPossible = true,
    String? recipientName,
    String? deliveryNote,
  }) async {
    String body = capsule.body;

    if (capsule.isEncrypted) {
      if (decryptIfPossible && passphrase != null && passphrase.trim().isNotEmpty) {
        body = await LegacyVaultService.instance.decryptBody(
          capsule: capsule,
          passphrase: passphrase,
        );
      } else {
        body = '(Encrypted capsule — export is intentionally redacted. Provide the passphrase to decrypt.)';
      }
    }

    final doc = pw.Document();
    final now = DateTime.now().toLocal();
    final title = capsule.title.trim().isEmpty ? 'Legacy Capsule' : capsule.title.trim();

    pw.Widget smallLabel(String text) => pw.Text(text, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(48),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Neura Companion — Legacy Vault',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(title, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  smallLabel('Generated'),
                  pw.Text('$now', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Details', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    pw.Text('Encrypted: ${capsule.isEncrypted ? 'yes' : 'no'}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Sealed: ${capsule.isSealed ? 'yes' : 'no'}', style: const pw.TextStyle(fontSize: 10)),
                    if (capsule.unlockAt != null)
                      pw.Text('Time‑lock: ${capsule.unlockAt!.toLocal()}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text('Created: ${capsule.createdAt.toLocal()}', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Updated: ${capsule.updatedAt.toLocal()}', style: const pw.TextStyle(fontSize: 10)),
                if (recipientName != null && recipientName.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Text('To: ${recipientName.trim()}', style: const pw.TextStyle(fontSize: 11)),
                ],
              ],
            ),
          ),

          if (deliveryNote != null && deliveryNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.lightBlue50,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: PdfColors.lightBlue200),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Delivery note', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Text(deliveryNote.trim(), style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],

          if (capsule.recipients.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Recipients (saved in capsule)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: capsule.recipients.map((r) => pw.Text('• $r', style: const pw.TextStyle(fontSize: 10))).toList(),
            ),
          ],

          if (capsule.tags.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Tags', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(capsule.tags.join(', '), style: const pw.TextStyle(fontSize: 10)),
          ],

          pw.SizedBox(height: 14),
          pw.Text('Message', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(body.trim().isEmpty ? '(Empty message)' : body, style: const pw.TextStyle(fontSize: 12)),

          if (capsule.attachments.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('Attachments', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: capsule.attachments
                  .map((p) => pw.Text('• ${p.split('/').last}', style: const pw.TextStyle(fontSize: 10)))
                  .toList(),
            ),
          ],

          pw.SizedBox(height: 18),
          pw.Divider(),
          pw.Text(
            'Reminder: protect sensitive info. If encryption was used, keep passphrases safe and separate.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    return _writeTempPdf(bytes, capsuleId: capsule.id);
  }

  Future<File> _writeTempPdf(Uint8List bytes, {required String capsuleId}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/legacy_${capsuleId}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
