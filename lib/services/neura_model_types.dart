enum NeuraModelProvider { openAi, anthropic }

extension NeuraModelProviderLabel on NeuraModelProvider {
  String get label => this == NeuraModelProvider.openAi ? 'OpenAI' : 'Anthropic';
}
