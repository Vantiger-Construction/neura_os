import '../rust_bridge/frb_generated.dart';
import '../rust_bridge/api.dart' as rust_api;

/// Thin Dart wrapper around the `neura_swarm` Rust crate (see `rust/`).
/// Runs the chat swarm's critic + memory-extractor agents concurrently for
/// a finished chat turn -- the primary streamed reply itself stays exactly
/// as it was, driven by [NeuraAiService]; this only adds the two new agents
/// alongside it.
class NeuraSwarmService {
  NeuraSwarmService._();
  static final NeuraSwarmService instance = NeuraSwarmService._();

  bool _initialized = false;

  /// Loads the native library and forwards the same Anthropic API key
  /// already baked into the build for [NeuraAiService]. Never persisted to
  /// disk by Rust -- kept in memory only, matching how the key is already
  /// scoped. Safe to call more than once.
  Future<void> init(String apiKey) async {
    if (!_initialized) {
      await RustLib.init();
      _initialized = true;
    }
    if (apiKey.isEmpty) return;
    rust_api.init(apiKey: apiKey);
  }

  /// Runs the critic + memory-extractor agents for one finished chat turn.
  /// Never throws -- a swarm-agent failure degrades to "no concern, no
  /// facts" inside Rust rather than surfacing an error, since the primary
  /// reply has already been shown by the time this is called.
  Future<SwarmOutcome> reviewAndExtract({
    required String transcript,
    required String draftReply,
    required String userMessage,
  }) async {
    if (!_initialized) return const SwarmOutcome(concernNote: null, facts: []);
    final raw = await rust_api.reviewAndExtract(
      transcript: transcript,
      draftReply: draftReply,
      userMessage: userMessage,
    );
    return SwarmOutcome._fromRust(raw);
  }
}

/// Dart-side mirror of the Rust `SwarmOutcome` -- flattens the generated
/// verdict enum into a nullable `concernNote` (null means "pass") since
/// that's the only thing chat UI code needs to branch on.
class SwarmOutcome {
  final String? concernNote;
  final List<SwarmFact> facts;

  const SwarmOutcome({required this.concernNote, required this.facts});

  factory SwarmOutcome._fromRust(rust_api.SwarmOutcome raw) {
    final verdict = raw.verdict;
    final note = verdict is rust_api.SwarmVerdict_Concern ? verdict.note : null;
    return SwarmOutcome(
      concernNote: note,
      facts: raw.facts
          .map((f) => SwarmFact(summary: f.summary, kind: f.kind))
          .toList(),
    );
  }
}

class SwarmFact {
  final String summary;
  final String kind;
  const SwarmFact({required this.summary, required this.kind});
}
