import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../modules/vault/memory_vault_models.dart';
import '../modules/vault/memory_vault_store.dart';
import 'portable_backup_codec.dart';
import 'scheduled_backup_settings.dart';
import 'vault_item_source.dart';

/// Result of decrypting and checksumming a backup without importing it.
class BackupVerificationResult {
  const BackupVerificationResult({
    required this.isValid,
    this.error,
    this.itemCount,
  });

  final bool isValid;
  final String? error;
  final int? itemCount;
}

enum ScheduledBackupStatus { skipped, succeeded, failed }

/// Outcome of one [PortableVaultBackupService.runScheduledBackupIfDue] call.
class ScheduledBackupRunResult {
  const ScheduledBackupRunResult._(this.status, {this.reason, this.itemCount});

  factory ScheduledBackupRunResult.skipped(String reason) =>
      ScheduledBackupRunResult._(ScheduledBackupStatus.skipped, reason: reason);

  factory ScheduledBackupRunResult.succeeded({int? itemCount}) =>
      ScheduledBackupRunResult._(
        ScheduledBackupStatus.succeeded,
        itemCount: itemCount,
      );

  factory ScheduledBackupRunResult.failed(String reason) =>
      ScheduledBackupRunResult._(ScheduledBackupStatus.failed, reason: reason);

  final ScheduledBackupStatus status;
  final String? reason;
  final int? itemCount;
}

class PortableVaultBackupService {
  PortableVaultBackupService({
    PortableBackupCodec? codec,
    VaultItemSource? store,
    ScheduledBackupSettings? scheduledSettings,
    Future<Directory> Function()? backupDirectory,
  })  : _codec = codec ?? PortableBackupCodec(),
        _store = store ?? MemoryVaultStore.instance,
        _scheduledSettings =
            scheduledSettings ?? ScheduledBackupSettings.instance,
        _backupDirectory = backupDirectory ?? _defaultBackupDirectory;

  static const _payloadVersion = 1;
  static const _maxBackupBytes = 25 * 1024 * 1024;
  static const scheduledBackupFileName = 'neura-scheduled.neurabackup';

  final PortableBackupCodec _codec;
  final VaultItemSource _store;
  final ScheduledBackupSettings _scheduledSettings;
  final Future<Directory> Function() _backupDirectory;

  static Future<Directory> _defaultBackupDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}backups',
    );
    await dir.create(recursive: true);
    return dir;
  }

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
    final items = _parseVaultPayload(payload);
    return _store.importItems(pin: pin, imported: items);
  }

  /// Decrypts and checksums [envelope] -- parsing every entry -- without
  /// ever calling [VaultItemSource.importItems]. Used both to self-verify a
  /// scheduled backup before it replaces the previous one, and to let the
  /// user check an existing backup's integrity on demand.
  Future<BackupVerificationResult> verifyBackupIntegrity(
    String envelope, {
    required String passphrase,
  }) async {
    try {
      final payload = await _codec.decrypt(
        envelope: envelope,
        passphrase: passphrase,
      );
      final items = _parseVaultPayload(payload);
      return BackupVerificationResult(isValid: true, itemCount: items.length);
    } catch (error) {
      return BackupVerificationResult(isValid: false, error: error.toString());
    }
  }

  List<VaultItem> _parseVaultPayload(Map<String, dynamic> payload) {
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
    return items;
  }

  Future<File> scheduledBackupFile() async {
    final dir = await _backupDirectory();
    return File('${dir.path}${Platform.pathSeparator}$scheduledBackupFileName');
  }

  /// Runs a scheduled backup when the feature is enabled, a passphrase has
  /// been configured, enough time has passed since the last run, and the
  /// vault is already unlocked this session -- [pin] must come from an
  /// existing unlock (e.g. [VaultSession.sessionPin]); this method never
  /// prompts for one itself.
  ///
  /// Every write is self-verified (decrypt + parse every entry) before it
  /// replaces the previous scheduled backup file, so a corrupted write can
  /// never silently become the only copy on disk.
  Future<ScheduledBackupRunResult> runScheduledBackupIfDue({
    required String pin,
    Duration interval = const Duration(hours: 24),
    DateTime? now,
  }) async {
    if (!_scheduledSettings.enabled) {
      return ScheduledBackupRunResult.skipped('disabled');
    }
    final passphrase = await _scheduledSettings.passphrase();
    if (passphrase == null || passphrase.isEmpty) {
      return ScheduledBackupRunResult.skipped('no passphrase configured');
    }

    final effectiveNow = now ?? DateTime.now();
    final lastRun = _scheduledSettings.lastRunAt;
    if (lastRun != null && effectiveNow.difference(lastRun) < interval) {
      return ScheduledBackupRunResult.skipped('not due yet');
    }

    try {
      final items = await _store.getItems(pin: pin);
      final envelope = await _codec.encrypt(
        passphrase: passphrase,
        payload: {
          'type': 'neura-memory-vault',
          'version': _payloadVersion,
          'createdAt': effectiveNow.toUtc().toIso8601String(),
          'items': items.map((item) => item.toJson()).toList(),
        },
      );

      final verification =
          await verifyBackupIntegrity(envelope, passphrase: passphrase);
      if (!verification.isValid) {
        final error = verification.error ?? 'verification failed';
        await _scheduledSettings.recordOutcome(
          at: effectiveNow,
          outcome: ScheduledBackupOutcome.failed,
          error: error,
        );
        return ScheduledBackupRunResult.failed(error);
      }

      final file = await scheduledBackupFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(envelope, flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);

      await _scheduledSettings.recordOutcome(
        at: effectiveNow,
        outcome: ScheduledBackupOutcome.success,
      );
      return ScheduledBackupRunResult.succeeded(itemCount: items.length);
    } catch (error) {
      await _scheduledSettings.recordOutcome(
        at: effectiveNow,
        outcome: ScheduledBackupOutcome.failed,
        error: error.toString(),
      );
      return ScheduledBackupRunResult.failed(error.toString());
    }
  }

  String _dateStamp() {
    final now = DateTime.now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
  }
}
