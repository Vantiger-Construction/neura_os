enum InteractionChannel {
  chat,
  call,
  meeting,
  note,
}

class InteractionRecord {
  final String id;
  final String profileId;
  final DateTime timestamp;
  final InteractionChannel channel;
  final String contextSnippet;
  final int yourMood; // -2..+2
  final int theirMood; // -2..+2
  final String summary;
  final String nextStep;

  InteractionRecord({
    required this.id,
    required this.profileId,
    required this.timestamp,
    required this.channel,
    required this.contextSnippet,
    required this.yourMood,
    required this.theirMood,
    required this.summary,
    required this.nextStep,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'timestamp': timestamp.toIso8601String(),
        'channel': channel.name,
        'contextSnippet': contextSnippet,
        'yourMood': yourMood,
        'theirMood': theirMood,
        'summary': summary,
        'nextStep': nextStep,
      };

  factory InteractionRecord.fromJson(Map<String, dynamic> json) {
    return InteractionRecord(
      id: json['id'] as String,
      profileId: json['profileId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      channel: InteractionChannel.values.firstWhere(
        (c) => c.name == (json['channel'] as String? ?? 'chat'),
        orElse: () => InteractionChannel.chat,
      ),
      contextSnippet: json['contextSnippet'] as String? ?? '',
      yourMood: (json['yourMood'] as num?)?.toInt() ?? 0,
      theirMood: (json['theirMood'] as num?)?.toInt() ?? 0,
      summary: json['summary'] as String? ?? '',
      nextStep: json['nextStep'] as String? ?? '',
    );
  }
}
