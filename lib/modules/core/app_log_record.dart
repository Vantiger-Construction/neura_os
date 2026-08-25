/// Shared structured-log schema and privacy boundary for every Neura target.
///
/// Values are made JSON-safe, bounded, and stripped of common credentials and
/// user-authored content before either the IO or web logger persists them.
class AppLogRecordFactory {
  AppLogRecordFactory({
    required this.platform,
    DateTime? sessionStartedAt,
  }) : sessionId = _newSessionId(sessionStartedAt ?? DateTime.now().toUtc());

  static const int schemaVersion = 2;

  final String platform;
  final String sessionId;
  int _sequence = 0;

  Map<String, Object?> build({
    required String level,
    required String event,
    required Map<String, Object?> data,
    DateTime? at,
  }) {
    return <String, Object?>{
      'v': schemaVersion,
      'ts': (at ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
      'seq': ++_sequence,
      'session': sessionId,
      'platform': platform,
      'level': AppLogSanitizer.event(level),
      'event': AppLogSanitizer.event(event),
      'data': AppLogSanitizer.map(data),
    };
  }

  static String _newSessionId(DateTime startedAt) {
    final micros = startedAt.microsecondsSinceEpoch.toRadixString(36);
    return 'session-$micros';
  }
}

class AppLogSanitizer {
  AppLogSanitizer._();

  static const int _maxEventCharacters = 240;
  static const int _maxStringCharacters = 8192;
  static const int _maxCollectionEntries = 64;
  static const int _maxDepth = 6;

  static final RegExp _secretKey = RegExp(
    r'(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|credential|cookie|session(?:[_-]?(?:id|token))?|private[_-]?key)',
    caseSensitive: false,
  );
  static const Set<String> _contentKeySuffixes = <String>{
    'body',
    'content',
    'contextsnippet',
    'dream',
    'input',
    'journal',
    'note',
    'output',
    'payload',
    'prompt',
    'query',
    'rawdata',
    'reply',
    'response',
    'summary',
    'text',
    'transcript',
    'usermessage',
  };
  static const Set<String> _exactBinaryContentKeys = <String>{
    'audio',
    'bytes',
    'image',
    'raw',
  };
  static final RegExp _bearer = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+\-/]+=*',
    caseSensitive: false,
  );
  static final RegExp _providerKey = RegExp(
    r'\b(?:sk-ant-|sk-|sbp_|ghp_|github_pat_)[A-Za-z0-9_\-]{12,}',
    caseSensitive: false,
  );
  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
  );
  static final RegExp _assignedSecret = RegExp(
    r'\b(api[_-]?key|password|secret|token|credential)\s*[:=]\s*([^\s,;]+)',
    caseSensitive: false,
  );
  static final RegExp _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _windowsUserPath = RegExp(
    r'([A-Za-z]:\\Users\\)[^\\\r\n]+',
    caseSensitive: false,
  );
  static final RegExp _unixUserPath = RegExp(
    r'(/(?:home|Users)/)[^/\r\n]+',
  );
  static final RegExp _urlQuery = RegExp(
    r'(https?://[^\s?#]+)[?#][^\s]+',
    caseSensitive: false,
  );

  static String event(String value) =>
      _truncate(_sanitizeString(value), _maxEventCharacters);

  static Map<String, Object?> map(Map<String, Object?> value) {
    return Map<String, Object?>.unmodifiable(
      _sanitizeMap(value, depth: 0),
    );
  }

  static Map<String, Object?> _sanitizeMap(
    Map<Object?, Object?> value, {
    required int depth,
  }) {
    if (depth >= _maxDepth) {
      return const <String, Object?>{'truncated': '[MAX_DEPTH]'};
    }
    final result = <String, Object?>{};
    var count = 0;
    for (final entry in value.entries) {
      if (count++ >= _maxCollectionEntries) {
        result['_truncated'] = value.length - _maxCollectionEntries;
        break;
      }
      final key = event(entry.key?.toString() ?? 'null');
      if (_secretKey.hasMatch(key)) {
        result[key] = '[REDACTED]';
      } else if (_isContentKey(key)) {
        result[key] = '[CONTENT_REDACTED]';
      } else {
        result[key] = _sanitizeValue(
          entry.value,
          depth: depth + 1,
        );
      }
    }
    return result;
  }

  static Object? _sanitizeValue(Object? value, {required int depth}) {
    if (value == null || value is bool || value is num) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map<Object?, Object?>) {
      return _sanitizeMap(value, depth: depth);
    }
    if (value is Iterable<Object?>) {
      if (depth >= _maxDepth) return const <Object?>['[MAX_DEPTH]'];
      final result = <Object?>[];
      var count = 0;
      for (final item in value) {
        if (count++ >= _maxCollectionEntries) {
          result.add('[TRUNCATED]');
          break;
        }
        result.add(_sanitizeValue(item, depth: depth + 1));
      }
      return result;
    }
    return _truncate(_sanitizeString(value.toString()), _maxStringCharacters);
  }

  static bool _isContentKey(String key) {
    final canonical = key.toLowerCase().replaceAll(
          RegExp('[^a-z0-9]'),
          '',
        );
    if (_exactBinaryContentKeys.contains(canonical)) return true;
    return _contentKeySuffixes.any(canonical.endsWith);
  }

  static String _sanitizeString(String input) {
    return input
        .replaceAll(_bearer, 'Bearer [REDACTED]')
        .replaceAll(_providerKey, '[REDACTED_KEY]')
        .replaceAll(_jwt, '[REDACTED_JWT]')
        .replaceAllMapped(
          _assignedSecret,
          (match) => '${match.group(1)}=[REDACTED]',
        )
        .replaceAll(_email, '[REDACTED_EMAIL]')
        .replaceAllMapped(
          _windowsUserPath,
          (match) => '${match.group(1)}<user>',
        )
        .replaceAllMapped(
          _unixUserPath,
          (match) => '${match.group(1)}<user>',
        )
        .replaceAllMapped(_urlQuery, (match) => '${match.group(1)}?[REDACTED]');
  }

  static String _truncate(String value, int maxCharacters) {
    if (value.length <= maxCharacters) return value;
    final omitted = value.length - maxCharacters;
    return '${value.substring(0, maxCharacters)}…[$omitted omitted]';
  }
}
