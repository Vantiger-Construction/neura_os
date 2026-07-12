import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models/legacy_capsule.dart';

/// Builds a simple "cover page" PDF to include inside a Legacy ZIP packet.
///
/// This is intentionally minimalist (no custom fonts, no assets) so it works
/// everywhere without extra setup.
class LegacyPdfCoverBuilder {
  LegacyPdfCoverBuilder._();

  static Future<Uint8List> buildCover({required LegacyCapsule capsule}) async {
    final doc = pw.Document();

    final title = capsule.title.trim().isEmpty ? 'Legacy Capsule' : capsule.title.trim();
    final now = DateTime.now().toLocal();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(48),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Neura Companion',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                'Legacy Delivery Packet',
                style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                title,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
              ),
              pw.SizedBox(height: 24),
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("What's inside", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 8),
                    pw.Bullet(text: 'capsule.json (message + metadata)'),
                    pw.Bullet(text: 'attachments/ (optional files)'),
                    pw.Bullet(text: 'README.txt (plain instructions)'),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                capsule.isEncrypted
                    ? 'Note: this capsule may be encrypted. If so, the recipient needs the passphrase you shared separately.'
                    : 'Note: this capsule is not encrypted.',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                capsule.unlockAt == null ? '' : 'Time‑lock: ${capsule.unlockAt!.toLocal()}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                'Generated: $now',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
