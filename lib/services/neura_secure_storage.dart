import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keep existing encryption keys on storage failures while v10 migrates v9
/// Android ciphers. A reset would make encrypted memories unrecoverable.
const neuraSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  ),
);
