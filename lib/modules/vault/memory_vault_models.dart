import 'dart:convert';

class VaultItem {
  final String id;
  final DateTime createdAt;
  final String title;
  final String body;
  final List<String> tags;

  const VaultItem({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.body,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'title': title,
        'body': body,
        'tags': tags,
      };

  static VaultItem fromJson(Map<String, dynamic> j) => VaultItem(
        id: j['id']?.toString() ?? '',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        tags: (j['tags'] is List) ? (j['tags'] as List).map((e) => e.toString()).toList() : const <String>[],
      );
}

String encodeVaultItems(List<VaultItem> list) => jsonEncode(list.map((e) => e.toJson()).toList());

List<VaultItem> decodeVaultItems(String raw) {
  if (raw.trim().isEmpty) return <VaultItem>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <VaultItem>[];
    final out = decoded.whereType<Map>().map((m) => VaultItem.fromJson(m.cast<String, dynamic>())).toList();
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  } catch (_) {
    return <VaultItem>[];
  }
}
