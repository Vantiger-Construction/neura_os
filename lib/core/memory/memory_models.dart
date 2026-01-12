import 'package:flutter/foundation.dart';

@immutable
class MemoryNode {
  final String id;
  final String content;
  final double weight;
  final Set<String> tags;
  final DateTime createdAtUtc;

  MemoryNode({
    required this.id,
    required this.content,
    this.weight = 0.5,
    Set<String>? tags,
    DateTime? createdAtUtc,
  })  : tags = tags ?? const <String>{},
        createdAtUtc = createdAtUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  MemoryNode copyWith({
    String? id,
    String? content,
    double? weight,
    Set<String>? tags,
    DateTime? createdAtUtc,
  }) {
    return MemoryNode(
      id: id ?? this.id,
      content: content ?? this.content,
      weight: weight ?? this.weight,
      tags: tags ?? this.tags,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    );
  }
}
