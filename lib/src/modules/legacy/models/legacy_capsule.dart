import 'dart:convert';

/// A single "Legacy Capsule" (message + optional attachments) stored locally.
///
/// This model is intentionally forward-compatible: new fields are optional when
/// reading older JSON exports.
class LegacyCapsule {
  final String id;
  final String title;

  /// Plaintext body *only* when not encrypted. When encrypted, this field may be
  /// empty and the encrypted payload fields are used instead.
  final String body;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Free-form recipients (names/emails/handles). For more structure, see
  /// Trusted Contacts in the Legacy module.
  final List<String> recipients;

  final List<String> tags;

  /// Optional time-lock.
  final DateTime? unlockAt;

  /// If sealed, Neura treats the capsule as read-only (duplicate to edit).
  final bool isSealed;

  // Encryption fields
  final bool isEncrypted;
  final String? cipherTextB64;
  final String? nonceB64;
  final String? macB64;
  final String? saltB64;

  /// Relative paths (inside the Legacy Vault folder) to attachments.
  final List<String> attachments;

  // Delivery / Legacy Guard fields (optional)

  /// If true, this capsule is intended to be included in "delivery packets".
  final bool deliveryEnabled;

  /// Delivery trigger hint:
  /// - manual: user decides when to share
  /// - unlock: intended for sharing after unlockAt
  /// - deadman: intended for sharing when Legacy Guard triggers
  final String deliveryTrigger;

  /// Preferred packet format: zip | pdf | json
  final String deliveryFormat;

  /// Optional references to TrustedContact IDs (if you use that feature).
  /// If empty, the free-form [recipients] list is used.
  final List<String> deliveryContactIds;

  const LegacyCapsule({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.recipients = const [],
    this.tags = const [],
    this.unlockAt,
    this.isSealed = false,
    this.isEncrypted = false,
    this.cipherTextB64,
    this.nonceB64,
    this.macB64,
    this.saltB64,
    this.attachments = const [],
    this.deliveryEnabled = false,
    this.deliveryTrigger = 'manual',
    this.deliveryFormat = 'zip',
    this.deliveryContactIds = const [],
  });

  bool get isLocked => unlockAt != null && DateTime.now().isBefore(unlockAt!);

  LegacyCapsule copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? recipients,
    List<String>? tags,
    DateTime? unlockAt,
    bool? isSealed,
    bool? isEncrypted,
    String? cipherTextB64,
    String? nonceB64,
    String? macB64,
    String? saltB64,
    List<String>? attachments,
    bool? deliveryEnabled,
    String? deliveryTrigger,
    String? deliveryFormat,
    List<String>? deliveryContactIds,
  }) {
    return LegacyCapsule(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      recipients: recipients ?? this.recipients,
      tags: tags ?? this.tags,
      unlockAt: unlockAt ?? this.unlockAt,
      isSealed: isSealed ?? this.isSealed,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      cipherTextB64: cipherTextB64 ?? this.cipherTextB64,
      nonceB64: nonceB64 ?? this.nonceB64,
      macB64: macB64 ?? this.macB64,
      saltB64: saltB64 ?? this.saltB64,
      attachments: attachments ?? this.attachments,
      deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
      deliveryTrigger: deliveryTrigger ?? this.deliveryTrigger,
      deliveryFormat: deliveryFormat ?? this.deliveryFormat,
      deliveryContactIds: deliveryContactIds ?? this.deliveryContactIds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'recipients': recipients,
      'tags': tags,
      'unlockAt': unlockAt?.toIso8601String(),
      'isSealed': isSealed,
      'isEncrypted': isEncrypted,
      'cipherTextB64': cipherTextB64,
      'nonceB64': nonceB64,
      'macB64': macB64,
      'saltB64': saltB64,
      'attachments': attachments,
      'deliveryEnabled': deliveryEnabled,
      'deliveryTrigger': deliveryTrigger,
      'deliveryFormat': deliveryFormat,
      'deliveryContactIds': deliveryContactIds,
    };
  }

  factory LegacyCapsule.fromMap(Map<String, dynamic> map) {
    List<String> list(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      return const [];
    }

    DateTime? date(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    String str(dynamic v, String fallback) {
      if (v == null) return fallback;
      final s = v.toString();
      return s.isEmpty ? fallback : s;
    }

    return LegacyCapsule(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      recipients: list(map['recipients']),
      tags: list(map['tags']),
      unlockAt: date(map['unlockAt']),
      isSealed: map['isSealed'] == true,
      isEncrypted: map['isEncrypted'] == true,
      cipherTextB64: map['cipherTextB64']?.toString(),
      nonceB64: map['nonceB64']?.toString(),
      macB64: map['macB64']?.toString(),
      saltB64: map['saltB64']?.toString(),
      attachments: list(map['attachments']),
      deliveryEnabled: map['deliveryEnabled'] == true,
      deliveryTrigger: str(map['deliveryTrigger'], 'manual'),
      deliveryFormat: str(map['deliveryFormat'], 'zip'),
      deliveryContactIds: list(map['deliveryContactIds']),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory LegacyCapsule.fromJson(String source) =>
      LegacyCapsule.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
