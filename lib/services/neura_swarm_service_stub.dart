/// Non-native fallback used on web, where Neura does not currently package a
/// WASM build of the Rust swarm. The primary Dart AI path remains independent.
class NeuraSwarmService {
  NeuraSwarmService._();
  static final NeuraSwarmService instance = NeuraSwarmService._();

  Future<void> init(String apiKey) {
    return Future<void>.error(
      UnsupportedError('The native Neura swarm is unavailable on web.'),
    );
  }

  Future<void> clearCredential() async {}

  Future<void> clearCredentialForDataWipe() async {}

  Future<SwarmOutcome> reviewAndExtract({
    required String transcript,
    required String draftReply,
    required String userMessage,
  }) async {
    return const SwarmOutcome(concernNote: null, facts: []);
  }
}

class SwarmOutcome {
  final String? concernNote;
  final List<SwarmFact> facts;

  const SwarmOutcome({required this.concernNote, required this.facts});
}

class SwarmFact {
  final String summary;
  final String kind;

  const SwarmFact({required this.summary, required this.kind});
}
