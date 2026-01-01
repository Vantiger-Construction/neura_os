import 'dart:convert';

class KindnessAct {
  final DateTime timestamp;
  final String category; // e.g. text, help, donate, volunteer
  final String note;

  const KindnessAct({
    required this.timestamp,
    required this.category,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'category': category,
        'note': note,
      };

  static KindnessAct fromJson(Map<String, dynamic> j) => KindnessAct(
        timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? '') ?? DateTime.now(),
        category: (j['category']?.toString() ?? 'other').trim().isEmpty ? 'other' : j['category'].toString(),
        note: (j['note']?.toString() ?? ''),
      );

  static String encodeList(List<KindnessAct> list) => jsonEncode(list.map((e) => e.toJson()).toList());

  static List<KindnessAct> decodeList(String raw) {
    if (raw.trim().isEmpty) return <KindnessAct>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <KindnessAct>[];
      return decoded.whereType<Map>().map((m) => KindnessAct.fromJson(m.cast<String, dynamic>())).toList();
    } catch (_) {
      return <KindnessAct>[];
    }
  }
}
