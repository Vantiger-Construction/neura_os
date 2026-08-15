import 'dart:convert';

class TrustedContact {
  final String id;
  final String displayName;
  final String address; // email / handle / phone label
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TrustedContact({
    required this.id,
    required this.displayName,
    required this.address,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  TrustedContact copyWith({
    String? id,
    String? displayName,
    String? address,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrustedContact(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      address: address ?? this.address,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'address': address,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TrustedContact.fromMap(Map<String, dynamic> map) {
    return TrustedContact(
      id: map['id']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      note: map['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory TrustedContact.fromJson(String s) =>
      TrustedContact.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
