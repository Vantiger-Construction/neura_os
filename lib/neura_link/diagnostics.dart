class DiagnosticCheck {
  const DiagnosticCheck({required this.name, required this.status, required this.remedy, this.detail});
  final String name;
  final String status;
  final String remedy;
  final String? detail;
  bool get isHealthy => status == 'ok' || status == 'healthy' || status == 'pass';
  factory DiagnosticCheck.fromJson(Map<String, dynamic> json) => DiagnosticCheck(
    name: json['name'] as String? ?? 'unknown', status: json['status'] as String? ?? 'unknown',
    remedy: json['remedy'] as String? ?? 'No remedy supplied.', detail: json['detail'] as String?,
  );
}

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({required this.checks, this.generatedAt});
  final List<DiagnosticCheck> checks;
  final DateTime? generatedAt;
  factory DiagnosticsSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['checks'] as List? ?? const [];
    return DiagnosticsSnapshot(
      checks: raw.whereType<Map>().map((v) => DiagnosticCheck.fromJson(Map<String, dynamic>.from(v))).toList(growable: false),
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? ''),
    );
  }
}

