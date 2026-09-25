enum NeuraModelProvider { openAi, anthropic }

/// The one place the Anthropic model is chosen, shared by the streaming and
/// non-streaming transports.
const String kNeuraAnthropicModel = 'claude-opus-5';

/// Opus 5 thinks adaptively by default. Chat is spoken aloud, so keep the
/// wait before the first word short; raise this for deeper replies.
const String kNeuraAnthropicEffort = 'medium';

extension NeuraModelProviderLabel on NeuraModelProvider {
  String get label {
    return switch (this) {
      NeuraModelProvider.openAi => 'OpenAI',
      NeuraModelProvider.anthropic => 'Anthropic',
    };
  }
}
