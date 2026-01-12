/// Data models for memory storage
class Memory {
  final String id;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  
  Memory({
    required this.id,
    required this.content,
    required this.timestamp,
    this.metadata = const {},
  });
  
  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

class MemorySearchResult {
  final Memory memory;
  final double relevance;
  
  MemorySearchResult({
    required this.memory,
    required this.relevance,
  });
}
