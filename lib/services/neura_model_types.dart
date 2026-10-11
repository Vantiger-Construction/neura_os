enum NeuraModelProvider { openAi, anthropic }

final class NeuraModelProfile {
  const NeuraModelProfile({
    required this.provider,
    required this.model,
    required this.reasoningEffort,
    required this.displayName,
    this.defaultForProvider = false,
  });

  final NeuraModelProvider provider;
  final String model;
  final String reasoningEffort;
  final String displayName;
  final bool defaultForProvider;

  Map<String, Object?> toJson() => {
        'provider': provider.name,
        'model': model,
        'reasoning_effort': reasoningEffort,
        'display_name': displayName,
        'default_for_provider': defaultForProvider,
      };
}

const kNeuraOpenAiDefaultProfile = NeuraModelProfile(
  provider: NeuraModelProvider.openAi,
  model: 'gpt-5.6-luna',
  reasoningEffort: 'low',
  displayName: 'GPT-5.6 Luna',
  defaultForProvider: true,
);

const kNeuraOpenAiGpt6LunaProfile = NeuraModelProfile(
  provider: NeuraModelProvider.openAi,
  model: 'gpt-6-luna',
  reasoningEffort: 'low',
  displayName: 'GPT-6 Luna',
);

const kNeuraOpenAiGpt61SolProfile = NeuraModelProfile(
  provider: NeuraModelProvider.openAi,
  model: 'gpt-6.1-sol',
  reasoningEffort: 'medium',
  displayName: 'GPT-6.1 Sol',
);

const kNeuraAnthropicDefaultProfile = NeuraModelProfile(
  provider: NeuraModelProvider.anthropic,
  model: 'claude-opus-5',
  reasoningEffort: 'medium',
  displayName: 'Claude Opus 5',
  defaultForProvider: true,
);

abstract final class NeuraModelProfiles {
  static const openAiComparisonProfiles = <NeuraModelProfile>[
    kNeuraOpenAiDefaultProfile,
    kNeuraOpenAiGpt6LunaProfile,
    kNeuraOpenAiGpt61SolProfile,
  ];

  static const allApproved = <NeuraModelProfile>[
    ...openAiComparisonProfiles,
    kNeuraAnthropicDefaultProfile,
  ];

  static NeuraModelProfile defaultFor(NeuraModelProvider provider) =>
      switch (provider) {
        NeuraModelProvider.openAi => kNeuraOpenAiDefaultProfile,
        NeuraModelProvider.anthropic => kNeuraAnthropicDefaultProfile,
      };

  static List<NeuraModelProfile> comparisonProfilesFor(
    NeuraModelProvider provider,
  ) =>
      allApproved
          .where((profile) => profile.provider == provider)
          .toList(growable: false);
}

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
