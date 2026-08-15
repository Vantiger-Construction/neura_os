import 'dart:convert';

class Envelope {
  const Envelope(
      {required this.kind,
      required this.id,
      required this.data,
      this.version = 1});
  final int version;
  final String kind;
  final String id;
  final Map<String, dynamic> data;

  factory Envelope.fromJson(Map<String, dynamic> json) => Envelope(
        version: (json['v'] as num?)?.toInt() ?? 1,
        kind: json['kind'] as String? ?? 'unknown',
        id: json['id'] as String? ?? '',
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      );

  Map<String, dynamic> toJson() =>
      {'v': version, 'kind': kind, 'id': id, 'data': data};
  String encode() => jsonEncode(toJson());
}
