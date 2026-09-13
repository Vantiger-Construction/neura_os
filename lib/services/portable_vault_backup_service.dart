import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../modules/vault/memory_vault_models.dart';
import '../modules/vault/memory_vault_store.dart';
import 'portable_backup_codec.dart';

class PortableVaultBackupService {
  PortableVaultBackupService({
    PortableBackupCodec? codec,
    MemoryVaultStore? store,
  })  : _codec = codec ?? PortableBackupCodec(),
        _store = store ?? MemoryVaultStore.instance;

  static const _payloadVersion = 1;
  static const _maxBackupBytes = 25 * 1024 * 1024;

  final PortableBackupCodec _codec;
  final MemoryVaultStore _store;

  Future<String?> exportToFile({
    required String pin,
    required String passphrase,
  }) async {
    final items = await _store.getItems(pin: pin);
    final envelope = await _codec.encrypt(
      passphrase: passphrase,
      payload: {
        'type': 'neura-memory-vault',
        'version': _payloadVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
      },
    );

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export encrypted Neura backup',
      fileName: 'neura-vault-${_dateStamp()}.neurabackup',
      type: FileType.custom,
      allowedExtensions: const ['neurabackup'],
    );
    if (path == null) return null;

    final file = File(path);
    await file.writeAsString(envelope, flush: true);
    return file.path;
  }

  Future<int?> importFromFile({
    required String pin,
    required String passphrase,
  }) async {
    final selection = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import encrypted Neura backup',
      type: FileType.custom,
      allowedExtensions: const ['neurabackup'],
      allowMultiple: false,
      withData: false,
    );
    final path = selection?.files.single.path;
    if (path == null) return null;

    final file = File(path);
    final length = await file.length();
    if (length <= 0 || length > _maxBackupBytes) {
      throw const FormatException('The selected backup has an invalid size.');
    }
    final envelope = await file.readAsString();
    final payload = await _codec.decrypt(
      envelope: envelope,
      passphrase: passphrase,
    );
    if (payload['type'] != 'neura-memory-vault' ||
        payload['version'] != _payloadVersion ||
        payload['items'] is! List) {
      throw const FormatException(
        'This is not a supported Neura vault backup.',
      );
    }

    final items = <VaultItem>[];
    for (final raw in payload['items'] as List) {
      if (raw is! Map) {
        throw const FormatException('A backup entry is malformed.');
      }
      items.add(VaultItem.fromJson(raw.cast<String, dynamic>()));
    }
    return _store.importItems(pin: pin, imported: items);
  }

  String _dateStamp() {
    final now = DateTime.now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
  }
}
