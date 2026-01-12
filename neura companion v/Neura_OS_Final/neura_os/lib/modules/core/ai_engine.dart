/// A tiny local “AI core” so the app behaves intelligently even without network.
///
/// This is not a real LLM. It's a pragmatic rule-based brain with a sense of humor.
class NeuraAICore {
  NeuraAICore._();
  static final NeuraAICore instance = NeuraAICore._();

  String respond(String message) {
    final m = message.trim().toLowerCase();
    if (m.isEmpty) return 'Say the word. I am listening.';

    if (m.contains('anx') || m.contains('panic') || m.contains('stress')) {
      return 'Okay. Tiny mission: inhale for 4… hold 4… exhale 6. Again. You are not broken — just overloaded.';
    }

    if (m.contains('sad') || m.contains('down') || m.contains('depress')) {
      return 'I’m here. Want a gentle plan: 1) water 2) sunlight 3) text one safe human. Small wins count.';
    }

    if (m.contains('angry') || m.contains('mad') || m.contains('furious')) {
      return 'Anger is energy with a story attached. Before we swing the hammer: what exactly got violated — time, respect, trust?';
    }

    if (m.contains('help') || m.contains('what should i do')) {
      return 'Two options: (A) we pick one problem and shrink it to a 10‑minute task, or (B) we do a reset ritual first.';
    }

    if (m.contains('legacy')) {
      return 'Legacy Vault: write it now, encrypt it if needed, and future-you can stop reinventing the wheel at 2am.';
    }

    // Default: reflect + nudge.
    return 'Got it. What’s the *one* outcome you want from this — clarity, relief, or a plan?';
  }
}
