class NeuraChatRequest {
  final String systemMessage;
  final String userMessage;
  final Map<String, dynamic> metadata;

  const NeuraChatRequest({
    required this.systemMessage,
    required this.userMessage,
    required this.metadata,
  });
}
