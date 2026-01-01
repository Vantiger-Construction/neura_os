/// A tiny local “AI core” so the app behaves intelligently even without network.
///
/// This is not a real LLM. It's a pragmatic rule-based brain with a sense of humor.
import '../human/human_prefs_controller.dart';
import '../human/persona_profile.dart';

class NeuraAICore {
  NeuraAICore._();
  static final NeuraAICore instance = NeuraAICore._();

  String respond(String message) {
    final m = message.trim().toLowerCase();
    if (m.isEmpty) return 'Say the word. I am listening.';

    // Safety: self-harm / suicide signals. Keep it simple and supportive.
    if (m.contains('suicide') || m.contains('kill myself') || m.contains('end it') || m.contains('self harm')) {
      return 'I’m really sorry you’re feeling this. You deserve real support right now. '
          'If you’re in the U.S., you can call or text 988 (Suicide & Crisis Lifeline). '
          'If you’re elsewhere, I can help you find local crisis numbers. '
          'If you’re in immediate danger, call your local emergency number.';
    }

    final persona = HumanPrefsController.instance.prefs.value.persona;

    if (m.contains('anx') || m.contains('panic') || m.contains('stress')) {
      return _style(
        persona,
        gentle: 'Okay. Tiny mission: inhale for 4… hold 4… exhale 6. Again. You are not broken — just overloaded.',
        blunt: 'Breathe first. In 4… hold 4… out 6. Repeat. Your nervous system is screaming, not “failing.”',
      );
    }

    if (m.contains('sad') || m.contains('down') || m.contains('depress')) {
      return _style(
        persona,
        gentle: 'I’m here. Want a gentle plan: 1) water 2) sunlight 3) text one safe human. Small wins count.',
        blunt: 'Okay. Basic care stack: water → light → one safe message. No heroics required.',
      );
    }

    if (m.contains('angry') || m.contains('mad') || m.contains('furious')) {
      return _style(
        persona,
        gentle:
            'Anger is energy with a story attached. Before we swing the hammer: what exactly got violated — time, respect, trust?',
        blunt: 'Name the violation: time, respect, trust, boundaries — which one? Then we pick the next move.',
      );
    }

    if (m.contains('help') || m.contains('what should i do')) {
      return _style(
        persona,
        gentle: 'Two options: (A) we pick one problem and shrink it to a 10‑minute task, or (B) we do a reset ritual first.',
        blunt: 'Pick one: plan (10 minutes) or reset (2 minutes). Don’t choose “spiral.”',
      );
    }

    if (m.contains('legacy')) {
      return _style(
        persona,
        gentle: 'Legacy Vault: write it now, encrypt it if needed, and future-you can stop reinventing the wheel at 2am.',
        blunt: 'Legacy Vault exists because future-you forgets. Write it now. Protect it. Done.',
      );
    }

    // Default: reflect + nudge.
    final core = persona.depth > 0.65
        ? 'Got it. What story are you telling yourself about this, and what evidence supports it?'
        : 'Got it. What’s the one outcome you want — clarity, relief, or a plan?';

    return _sprinkle(persona, core);
  }
}

String _style(PersonaProfile p, {required String gentle, required String blunt}) {
  final base = p.directness > 0.65 ? blunt : gentle;
  return _sprinkle(p, base);
}

String _sprinkle(PersonaProfile p, String text) {
  final jokey = p.humor > 0.7;
  if (!jokey) return text;

  // Keep it small. Humor is garnish, not duct tape.
  const tags = [
    ' (No shame, just science.)',
    ' (Brains are weird. We work with it.)',
    ' (You are not a robot. I am. It’s unfair.)',
  ];
  final idx = ((p.energy * 10).round()) % tags.length;
  return '$text${tags[idx]}';
}
