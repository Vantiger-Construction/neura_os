class SupportResources {
  static const us = {
    '988': 'Call or text 988 (Suicide & Crisis Lifeline, US)',
    '911': 'If you are in immediate danger, call 911',
  };

  static const global = {
    'emergency':
        'If you are in immediate danger, contact your local emergency number.',
  };

  /// Returns reviewed crisis wording for the supplied locale. Unknown or
  /// country-less locales use the global emergency fallback rather than
  /// guessing that a US number applies.
  static String forLocale(String? localeName) {
    final normalized = (localeName ?? '').toLowerCase().replaceAll('-', '_');
    final localeParts = normalized.split('_');
    if (localeParts.contains('us')) {
      return '${us['988']}. ${us['911']}.';
    }
    return global['emergency']!;
  }
}
