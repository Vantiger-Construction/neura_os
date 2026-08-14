class TimelineVault {
  TimelineVault._();
  static final TimelineVault instance = TimelineVault._();
  final List<Map<String, dynamic>> _records = [];

  Future<void> initialize() async {}

  Future<void> append(
    String kind, {
    Map<String, Object?> data = const {},
    String source = 'neura_os',
  }) async {
    _records.add({
      'v': 1,
      'seq': _records.length + 1,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'kind': kind,
      'source': source,
      'data': data,
    });
  }

  Future<List<Map<String, dynamic>>> tail({int maxLines = 100}) async {
    final start = _records.length > maxLines ? _records.length - maxLines : 0;
    return List.unmodifiable(_records.sublist(start));
  }

  Future<String> exportCopy() async =>
      'Timeline export is available in the Windows and mobile builds.';
}
