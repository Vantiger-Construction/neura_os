import 'dart:convert';

/// Bounded, non-content record of a mood-trend share with a trusted contact.
///
/// Only counts and date ranges are kept -- never mood scores, notes, or the
/// generated summary text itself. This mirrors the same "dates and numeric
/// scores only" boundary used for the cloud-tool mood-history share.
class ContactShareRecord {
  final String id;
  final String contactId;
  final DateTime sharedAt;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int entryCount;

  const ContactShareRecord({
    required this.id,
    required this.contactId,
    required this.sharedAt,
    required this.rangeStart,
    required this.rangeEnd,
    required this.entryCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contactId': contactId,
      'sharedAt': sharedAt.toUtc().toIso8601String(),
      'rangeStart': rangeStart.toUtc().toIso8601String(),
      'rangeEnd': rangeEnd.toUtc().toIso8601String(),
      'entryCount': entryCount,
    };
  }

  factory ContactShareRecord.fromMap(Map<String, dynamic> map) {
    return ContactShareRecord(
      id: map['id'] as String? ?? '',
      contactId: map['contactId'] as String? ?? '',
      sharedAt: _parseDate(map['sharedAt']),
      rangeStart: _parseDate(map['rangeStart']),
      rangeEnd: _parseDate(map['rangeEnd']),
      entryCount: (map['entryCount'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime _parseDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  String toJson() => json.encode(toMap());

  factory ContactShareRecord.fromJson(String source) =>
      ContactShareRecord.fromMap(json.decode(source) as Map<String, dynamic>);
}
