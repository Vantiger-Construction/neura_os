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
  model: kNeuraAnthropicModel,
  reasoningEffort: kNeuraAnthropicEffort,
  displayName: 'Claude Opus 5.5',
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
const String kNeuraAnthropicModel = 'claude-opus-5-5';

/// Opus 5.5 always thinks adaptively; effort is the only depth control (it
/// defaults to `medium` on this model, but is set explicitly). Chat is spoken
/// aloud, so keep the wait before the first word short.
const String kNeuraAnthropicEffort = 'medium';

/// If a safety classifier declines a request, the API re-runs it server-side
/// on Anthropic's recommended fallback model instead of returning a refusal.
const String kNeuraAnthropicFallbackBeta = 'server-side-fallback-2026-07-01';
const String kNeuraAnthropicFallbacks = 'default';

extension NeuraModelProviderLabel on NeuraModelProvider {
  String get label {
    return switch (this) {
      NeuraModelProvider.openAi => 'OpenAI',
      NeuraModelProvider.anthropic => 'Anthropic',
    };
  }
}
