import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_model_comparison.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_model_stream.dart';
import 'package:neuro_companion/services/neura_model_types.dart';

void main() {
  const request = NeuraModelRequest(
    systemPrompt: 'Be kind.',
    messages: [
      {'role': 'user', 'content': 'Hello'},
    ],
    purpose: 'synthetic comparison',
    includesPrivateContext: false,
  );

  test(
    'approved OpenAI profiles include new candidates without moving default',
    () {
      expect(kNeuraOpenAiDefaultProfile.model, 'gpt-5.6-luna');
      expect(kNeuraOpenAiDefaultProfile.reasoningEffort, 'low');
      expect(NeuraModelProfiles.openAiComparisonProfiles.map((p) => p.model), [
        'gpt-5.6-luna',
        'gpt-6-luna',
        'gpt-6.1-sol',
      ]);
    },
  );

  test('OpenAI stream body uses the selected profile and effort', () {
    final transport = NeuraModelStreamTransport(
      NeuraModelProvider.openAi,
      profile: kNeuraOpenAiGpt61SolProfile,
    );

    final body = transport.buildBody('Be kind.', const [
      {'role': 'user', 'content': 'Hello'},
    ], const []);

    expect(body['model'], 'gpt-6.1-sol');
    expect(body['reasoning'], {'effort': 'medium'});
    expect(jsonEncode(body), isNot(contains('gpt-5.6-luna')));
  });

  test(
    'synthetic comparison requires approval per profile and makes no calls',
    () async {
      final harness = NeuraSyntheticModelComparisonHarness();
      final approvals = <String>[];
      final runs = <String>[];

      final results = await harness.compare(
        request: request,
        profiles: NeuraModelProfiles.openAiComparisonProfiles,
        requestApproval: (profile, _) async {
          approvals.add(profile.model);
          return profile != kNeuraOpenAiGpt6LunaProfile;
        },
        runner: (profile, _) async {
          runs.add(profile.model);
          return NeuraSyntheticModelResult(summary: 'mock ${profile.model}');
        },
      );

      expect(approvals, ['gpt-5.6-luna', 'gpt-6-luna', 'gpt-6.1-sol']);
      expect(runs, ['gpt-5.6-luna', 'gpt-6.1-sol']);
      expect(results.where((entry) => entry.completed), hasLength(2));
      expect(
        results
            .singleWhere(
              (entry) => entry.profile == kNeuraOpenAiGpt6LunaProfile,
            )
            .approved,
        isFalse,
      );
    },
  );
}
