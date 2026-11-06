import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Decrypted items held only for one explicit restore review. Revocation and
/// consumption discard the service's references; neither persists a second copy.
class PortableBackupPreview {
  PortableBackupPreview._(this._owner, List<VaultItem> items)
      : _items = List.unmodifiable(items.map((item) => VaultItem(
            id: item.id,
            createdAt: item.createdAt,
            title: item.title,
            body: item.body,
            tags: List.unmodifiable(item.tags))));
  final PortableVaultBackupService _owner;
  List<VaultItem> _items;
  bool _current = true;
  bool get isCurrent => _current;
  List<VaultItem> get items => _items;

  void revoke() {
    _current = false;
    _items = const [];
  }
}

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
  static bool _suspendedForWipe = false;
  static final _scheduledWrites = <Future<void>>{};

  static void suspendForDataWipe() => _suspendedForWipe = true;

  static Future<void> drainForDataWipe() async {
    await Future.wait(_scheduledWrites.toList())
        .timeout(const Duration(seconds: 30));
  }

  @visibleForTesting
  static void resetWipeGateForTesting() {
    if (_scheduledWrites.isNotEmpty) {
      throw StateError('Backups are still active.');
    }
    _suspendedForWipe = false;
  }

  static void _checkBackupWrite() {
    if (_suspendedForWipe) throw StateError('Backup cancelled by data wipe.');
  }

  bool _restoring = false;
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

    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export encrypted Neura backup',
      fileName: 'neura-vault-${_dateStamp()}.neurabackup',
      bytes: Uint8List.fromList(utf8.encode(envelope)),
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }

  /// Reads ciphertext only; the caller owns native picker and foreground checks.
  Future<String> readBackupFile(PlatformFile file,
      {bool Function()? mayRead}) async {
    void checkCurrent() {
      if (mayRead != null && !mayRead()) {
        throw StateError('Backup selection ended.');
      }
    }

    checkCurrent();
    final length = file.lengthSync();
    if (length != null && (length <= 0 || length > _maxBackupBytes)) {
      throw const FormatException('The selected backup has an invalid size.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      checkCurrent();
      if (bytes.length + chunk.length > _maxBackupBytes) {
        throw const FormatException('The selected backup has an invalid size.');
      }
      bytes.add(chunk);
    }
    checkCurrent();
    if (bytes.isEmpty) throw const FormatException('The backup is empty.');
    final envelope = utf8.decode(bytes.takeBytes());
    return envelope;
  }

  /// Verify/decrypt without writing to the live vault or reading existing items.
  Future<PortableBackupPreview> previewRestore(
    String envelope, {
    required String passphrase,
  }) async {
    if (envelope.length > _maxBackupBytes ||
        utf8.encode(envelope).length > _maxBackupBytes) {
      throw const FormatException('The backup is too large.');
    }
    final payload = await _codec.decrypt(
      envelope: envelope,
      passphrase: passphrase,
    );
    final items = _parseVaultPayload(payload);
    return PortableBackupPreview._(this, items);
  }

  Future<int> restorePreview(
      {required String pin,
      required PortableBackupPreview preview,
      required Set<int> selected,
      required bool Function() mayRestore}) async {
    if (_restoring || !mayRestore()) {
      throw StateError('Restore is unavailable. Review again.');
    }
    if (!identical(preview._owner, this) || !preview.isCurrent) {
      throw StateError('Verify this backup again before restoring.');
    }
    if (selected.isEmpty ||
        selected.any((i) => i < 0 || i >= preview.items.length)) {
      throw ArgumentError('Select existing backup entries.');
    }
    final items = [
      for (var i = 0; i < preview.items.length; i++)
        if (selected.contains(i)) preview.items[i]
    ];
    // Consume synchronously before the first write await. Double taps and
    // retries cannot re-use the prior review, even when a write fails.
    preview.revoke();
    _restoring = true;
    try {
      return await _store.importItems(
          pin: pin, imported: items, mayWrite: mayRestore);
    } finally {
      _restoring = false;
    }
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
      if (raw['id'] is! String ||
          (raw['id'] as String).trim().isEmpty ||
          raw['title'] is! String ||
          raw['body'] is! String ||
          raw['createdAt'] is! String ||
          DateTime.tryParse(raw['createdAt'] as String) == null ||
          raw['tags'] is! List ||
          !(raw['tags'] as List).every((tag) => tag is String)) {
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
  }) {
    if (_suspendedForWipe) {
      return Future.value(
          ScheduledBackupRunResult.skipped('data wipe in progress'));
    }
    final operation =
        _runScheduledBackupIfDue(pin: pin, interval: interval, now: now);
    // Track all instances, including a screen disposed while encryption runs.
    final drained =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _scheduledWrites.add(drained);
    unawaited(drained.whenComplete(() => _scheduledWrites.remove(drained)));
    return operation;
  }

  Future<ScheduledBackupRunResult> _runScheduledBackupIfDue({
    required String pin,
    required Duration interval,
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
      _checkBackupWrite();
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
      _checkBackupWrite();
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
      _checkBackupWrite();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(envelope, flush: true);
      _checkBackupWrite();
      if (await file.exists()) await file.delete();
      _checkBackupWrite();
      await tmp.rename(file.path);

      _checkBackupWrite();
      await _scheduledSettings.recordOutcome(
        at: effectiveNow,
        outcome: ScheduledBackupOutcome.success,
      );
      return ScheduledBackupRunResult.succeeded(itemCount: items.length);
    } catch (error) {
      if (_suspendedForWipe) {
        return ScheduledBackupRunResult.failed(
            'Backup cancelled by data wipe.');
      }
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
