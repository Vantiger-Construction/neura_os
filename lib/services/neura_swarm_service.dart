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

  /// Loads the native library and forwards the credential held by the secure
  /// provider store. Rust keeps it in memory only. Safe to call more than
  /// once when the user replaces or removes the credential.
  Future<void> init(String apiKey) async {
    if (!_initialized) {
      await RustLib.init();
      _initialized = true;
    }
    // Must be awaited: this crosses the FFI bridge and is the first
    // real call into the native library. Firing it without awaiting let
    // `boot()` flip `ready` (and kick off the mascot window's own native
    // engine spin-up) while this was still in flight -- the same
    // concurrent-first-native-call hazard documented in
    // MascotWindowService.initialCreationSettled, just via a new source.
    await rust_api.init(apiKey: apiKey);
  }

  /// Removes the provider credential from the native process as well as the
  /// Dart side. The secure store itself is owned by ProviderCredentials.
  Future<void> clearCredential() => init('');

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
