
enum PromiseStatus {
  pending,
  completed,
  dropped,
}

class NeuraPromise {
  final String id;
  final String? profileId;
  final String description;
  final DateTime createdAt;
  final DateTime? dueAt;
  final PromiseStatus status;

  NeuraPromise({
    required this.id,
    required this.description,
    required this.createdAt,
    this.profileId,
    this.dueAt,
    this.status = PromiseStatus.pending,
  });

  NeuraPromise copyWith({
    String? description,
    String? profileId,
    DateTime? createdAt,
    DateTime? dueAt,
    PromiseStatus? status,
  }) {
    return NeuraPromise(
      id: id,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      profileId: profileId ?? this.profileId,
      dueAt: dueAt ?? this.dueAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'status': status.name,
      };

  factory NeuraPromise.fromJson(Map<String, dynamic> json) {
    return NeuraPromise(
      id: json['id'] as String,
      profileId: json['profileId'] as String?,
      description: json['description'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueAt: (json['dueAt'] as String?) != null
          ? DateTime.parse(json['dueAt'] as String)
          : null,
      status: PromiseStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'pending'),
        orElse: () => PromiseStatus.pending,
      ),
    );
  }
}
