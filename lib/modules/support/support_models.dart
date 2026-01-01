import 'dart:convert';

class TrustedContact {
  final String id;
  final String name;
  final String phone;
  final String note;

  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'note': note,
      };

  static TrustedContact fromJson(Map<String, dynamic> j) => TrustedContact(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
      );
}

String encodeContacts(List<TrustedContact> list) => jsonEncode(list.map((e) => e.toJson()).toList());

List<TrustedContact> decodeContacts(String raw) {
  if (raw.trim().isEmpty) return <TrustedContact>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <TrustedContact>[];
    return decoded.whereType<Map>().map((m) => TrustedContact.fromJson(m.cast<String, dynamic>())).toList();
  } catch (_) {
    return <TrustedContact>[];
  }
}
