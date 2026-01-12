import 'dart:convert';

/// A reusable message template used when sharing a Legacy Packet.
///
/// Supported placeholders:
/// - {contactName}
/// - {capsuleTitle}
/// - {date}
/// - {appName}
class LegacyMessageTemplate {
  final String id;
  final String name;
  final String bodyTemplate;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LegacyMessageTemplate({
    required this.id,
    required this.name,
    required this.bodyTemplate,
    required this.createdAt,
    required this.updatedAt,
    this.isBuiltIn = false,
  });

  LegacyMessageTemplate copyWith({
    String? id,
    String? name,
    String? bodyTemplate,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LegacyMessageTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      bodyTemplate: bodyTemplate ?? this.bodyTemplate,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'bodyTemplate': bodyTemplate,
        'isBuiltIn': isBuiltIn,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LegacyMessageTemplate.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return LegacyMessageTemplate(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      bodyTemplate: map['bodyTemplate']?.toString() ?? '',
      isBuiltIn: map['isBuiltIn'] == true,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? now,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory LegacyMessageTemplate.fromJson(String source) =>
      LegacyMessageTemplate.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
