import 'package:flutter/foundation.dart';

import 'neura_error_redactor.dart';

/// Web fallback for the pre-plugin bootstrap log.
///
/// Browsers do not expose a dependency-free local file path, so retain the
/// same API and emit the already-redacted payload to the debug console.
class NeuraBootstrapLog {
  NeuraBootstrapLog._();

  static const String location = 'Browser console (local file unavailable)';
  static const String displayLocation = location;
  static bool _suspendedForDataWipe = false;

  static Future<void> append(Map<String, Object?> payload) async {
    if (_suspendedForDataWipe) return;
    debugPrint('[NeuraBootstrap] ${_sanitize(payload)}');
  }

  static Future<void> drain() async {}

  static Future<List<Map<String, Object?>>> tail({int maxRecords = 100}) async {
    return const [];
  }

  static Future<void> clear() async {}

  static Future<void> suspendForDataWipe() async {
    _suspendedForDataWipe = true;
  }

  static Future<String?> exportCopy({String? destinationPath}) async => null;

  static Map<String, Object?> _sanitize(Map<String, Object?> raw) {
    final errorType = NeuraErrorRedactor.tag(
      raw['error_type']?.toString() ?? '',
      fallback: 'UnknownError',
    );

    return <String, Object?>{
      'source': NeuraErrorRedactor.tag(raw['source']?.toString() ?? ''),
      'error_type': errorType,
      'message': 'An unexpected $errorType was contained.',
      'stack': NeuraErrorRedactor.stack(raw['stack']?.toString() ?? ''),
      'fatal': raw['fatal'] == true,
      'phase': NeuraErrorRedactor.tag(raw['phase']?.toString() ?? ''),
    };
  }
}
