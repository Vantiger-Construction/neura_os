enum NeuraModelProvider { openAi, anthropic }

extension NeuraModelProviderLabel on NeuraModelProvider {
  String get label {
    return switch (this) {
      NeuraModelProvider.openAi => 'OpenAI',
      NeuraModelProvider.anthropic => 'Anthropic',
    };
  }
}
