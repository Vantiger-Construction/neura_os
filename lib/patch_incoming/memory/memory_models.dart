/// Types of memory entries.
enum MemoryType { note, event, emotion, dream, insight }

/// A single memory node stored by Neura.
class MemoryNode {
  final String id;
  final MemoryType type;
  final String content;
  final double weight;
  final List<String> tags;
  final DateTime createdAt;

  MemoryNode({
    required this.id,
    required this.type,
    required this.content,
    required this.weight,
    this.tags = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'content': content,
    'weight': weight,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MemoryNode.fromMap(Map<String, dynamic> map) {
    return MemoryNode(
      id: map['id'] as String? ?? '',
      type: MemoryType.values.firstWhere(
        (t) => t.name == (map['type'] as String? ?? 'note'),
        orElse: () => MemoryType.note,
      ),
      content: map['content'] as String? ?? '',
      weight: (map['weight'] as num?)?.toDouble() ?? 0.5,
      tags: (map['tags'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
