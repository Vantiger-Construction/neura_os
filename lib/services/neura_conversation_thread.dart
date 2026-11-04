import 'dart:convert';

/// A small, editable session brief. Only verbatim user text is retained; no
/// model inference becomes a fact. This grants no memory or action permission.
class NeuraConversationThread {
  String _topic = '';
  String _correction = '';
  bool enabled = false;

  String get topic => _topic;
  String get correction => _correction;
  static const maxFieldBytes = 160;

  void update(String topic, String correction) {
    for (final value in [topic, correction]) {
      if (utf8.encode(value).length > maxFieldBytes ||
          value.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'))) {
        throw const FormatException('Keep each field within 160 UTF-8 bytes.');
      }
    }
    _topic = topic.trim();
    _correction = correction.trim();
  }

  void observeUserTurn(String text) {
    if (!enabled) return;
    final value = text.trim();
    // Never truncate a correction into a different meaning.
    if (utf8.encode(value).length > maxFieldBytes) return;
    if (_topic.isEmpty) _topic = value;
    if (RegExp(
            r'^(actually\b|correction\b|i meant\b|instead\b|change\b|make that\b)',
            caseSensitive: false)
        .hasMatch(value)) {
      _correction = value;
    }
  }

  String get context => !enabled || _topic.isEmpty
      ? ''
      : 'Earlier user topic: $_topic\n'
          '${_correction.isEmpty ? '' : 'Latest user correction: $_correction\n'}'
          'Newer user corrections take precedence. Ask if unclear.';

  void clear() {
    _topic = '';
    _correction = '';
    enabled = false;
  }
}
