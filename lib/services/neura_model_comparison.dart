import 'neura_model_router.dart';
import 'neura_model_types.dart';

typedef NeuraSyntheticModelRunner = Future<NeuraSyntheticModelResult> Function(
  NeuraModelProfile profile,
  NeuraModelRequest request,
);

typedef NeuraSyntheticModelApproval = Future<bool> Function(
    NeuraModelProfile profile, NeuraModelRequest request);

final class NeuraSyntheticModelResult {
  const NeuraSyntheticModelResult({
    required this.summary,
    this.latencyMs,
    this.metrics = const {},
  });

  final String summary;
  final int? latencyMs;
  final Map<String, num> metrics;
}

final class NeuraSyntheticModelComparisonEntry {
  const NeuraSyntheticModelComparisonEntry({
    required this.profile,
    required this.approved,
    this.result,
    this.error,
  });

  final NeuraModelProfile profile;
  final bool approved;
  final NeuraSyntheticModelResult? result;
  final Object? error;

  bool get completed => approved && result != null && error == null;
}

/// Runs provider-profile comparisons against a caller-supplied synthetic
/// runner. It never reads credentials, makes network calls, or changes the
/// production default model.
final class NeuraSyntheticModelComparisonHarness {
  const NeuraSyntheticModelComparisonHarness();

  Future<List<NeuraSyntheticModelComparisonEntry>> compare({
    required NeuraModelRequest request,
    required List<NeuraModelProfile> profiles,
    required NeuraSyntheticModelApproval requestApproval,
    required NeuraSyntheticModelRunner runner,
  }) async {
    final entries = <NeuraSyntheticModelComparisonEntry>[];
    for (final profile in profiles) {
      final approved = await requestApproval(profile, request);
      if (!approved) {
        entries.add(
          NeuraSyntheticModelComparisonEntry(profile: profile, approved: false),
        );
        continue;
      }
      try {
        entries.add(
          NeuraSyntheticModelComparisonEntry(
            profile: profile,
            approved: true,
            result: await runner(profile, request),
          ),
        );
      } catch (error) {
        entries.add(
          NeuraSyntheticModelComparisonEntry(
            profile: profile,
            approved: true,
            error: error,
          ),
        );
      }
    }
    return List.unmodifiable(entries);
  }
}
