/// Redacts common credential and user-path shapes before an error leaves the
/// in-memory exception pipeline.
///
/// This intentionally operates on strings instead of attempting to understand
/// a provider-specific payload. Bootstrap errors can happen before any of
/// Neura's normal configuration or logging services are available.
class NeuraErrorRedactor {
  NeuraErrorRedactor._();

  static const int _maxMessageCharacters = 4096;
  static const int _maxStackCharacters = 16384;

  static String message(String value) =>
      _sanitize(value, maxCharacters: _maxMessageCharacters);

  static String stack(String value) =>
      _sanitize(value, maxCharacters: _maxStackCharacters);

  static String tag(String value, {String fallback = 'unknown'}) {
    final sanitized = _sanitize(value, maxCharacters: 128)
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  static String _sanitize(String value, {required int maxCharacters}) {
    var result = value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\r\n]{4,}'), '\n\n\n');

    // Authorization values are removed first so a key/value pass cannot leave
    // the token behind after matching only the `Bearer` prefix.
    result = result.replaceAll(
      RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer <redacted>',
    );

    // Authorization headers and the most common config/JSON credential keys.
    result = result.replaceAllMapped(
      RegExp(
        r'(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|'
        r'client[_-]?secret|password)(["\x27]?)(\s*[=:]\s*)'
        r'("[^"]*"|\x27[^\x27]*\x27|[^\s,;}&]+)',
        caseSensitive: false,
      ),
      (match) => '${match[1]}${match[2]}${match[3]}<redacted>',
    );

    // Provider-style keys, including sk-live-*, sk-test-* and sk-proj-*.
    result = result.replaceAll(
      RegExp(r'\b(?:sk|pk|rk)[-_][A-Za-z0-9_-]{12,}\b'),
      '<redacted-key>',
    );
    result = result.replaceAll(
      RegExp(
        r'\b(?:gh[pousr]_|github_pat_|sbp_)[A-Za-z0-9_]{12,}\b',
        caseSensitive: false,
      ),
      '<redacted-token>',
    );

    // JWTs commonly appear as Supabase sessions and must be removed before
    // the dependency-free bootstrap file is written.
    result = result.replaceAll(
      RegExp(
        r'\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
      ),
      '<redacted-jwt>',
    );

    result = result.replaceAll(
      RegExp(
        r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        caseSensitive: false,
      ),
      '<redacted-email>',
    );

    // Sensitive URL query parameters. Preserve the parameter name to keep the
    // diagnostic useful without retaining its value.
    result = result.replaceAllMapped(
      RegExp(
        r'([?&](?:token|key|secret|password|code)=)[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match[1]}<redacted>',
    );

    // User home directories often reveal an account name. Keep enough of the
    // path to identify the platform while removing that identity.
    result = result.replaceAllMapped(
      RegExp(r'([A-Za-z]:\\Users\\)[^\\\r\n]+', caseSensitive: false),
      (match) => '${match[1]}<redacted>',
    );
    result = result.replaceAllMapped(
      RegExp(r'(/(?:Users|home)/)[^/\r\n]+'),
      (match) => '${match[1]}<redacted>',
    );

    if (result.length <= maxCharacters) return result;
    return '${result.substring(0, maxCharacters)}\n<truncated>';
  }
}
