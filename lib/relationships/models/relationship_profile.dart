class RelationshipProfile {
  final String id;
  final String name;
  final List<String> tags;
  final double careScore; // 0–100
  final DateTime? lastContact;
  final double avgMoodAfterInteractions; // -2..+2
  final int openPromiseCount;
  final String notes;

  RelationshipProfile({
    required this.id,
    required this.name,
    this.tags = const [],
    this.careScore = 50,
    this.lastContact,
    this.avgMoodAfterInteractions = 0,
    this.openPromiseCount = 0,
    this.notes = '',
  });

  RelationshipProfile copyWith({
    String? name,
    List<String>? tags,
    double? careScore,
    DateTime? lastContact,
    double? avgMoodAfterInteractions,
    int? openPromiseCount,
    String? notes,
  }) {
    return RelationshipProfile(
      id: id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      careScore: careScore ?? this.careScore,
      lastContact: lastContact ?? this.lastContact,
      avgMoodAfterInteractions:
          avgMoodAfterInteractions ?? this.avgMoodAfterInteractions,
      openPromiseCount: openPromiseCount ?? this.openPromiseCount,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags,
        'careScore': careScore,
        'lastContact': lastContact?.toIso8601String(),
        'avgMoodAfterInteractions': avgMoodAfterInteractions,
        'openPromiseCount': openPromiseCount,
        'notes': notes,
      };

  factory RelationshipProfile.fromJson(Map<String, dynamic> json) {
    return RelationshipProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      careScore: (json['careScore'] as num?)?.toDouble() ?? 50,
      lastContact: (json['lastContact'] as String?) != null
          ? DateTime.parse(json['lastContact'] as String)
          : null,
      avgMoodAfterInteractions:
          (json['avgMoodAfterInteractions'] as num?)?.toDouble() ?? 0,
      openPromiseCount: (json['openPromiseCount'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String? ?? '',
    );
  }
}
