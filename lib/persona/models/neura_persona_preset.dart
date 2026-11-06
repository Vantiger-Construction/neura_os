import 'persona_profile.dart';

/// Optional starting points. These describe Neura's delivery, not the person.
enum NeuraPersonaPreset {
  calm(
    'Calm companion',
    'Gentle words, quiet energy, room to breathe.',
    PersonaProfile(
        warmth: 0.9, directness: 0.3, humor: 0.2, energy: 0.2, depth: 0.5),
  ),
  playful(
    'Playful spark',
    'Light humor, lively presence, warm encouragement.',
    PersonaProfile(
        warmth: 0.8, directness: 0.5, humor: 0.8, energy: 0.8, depth: 0.4),
  ),
  practical(
    'Steady coach',
    'Clear answers and manageable next steps.',
    PersonaProfile(
        warmth: 0.6, directness: 0.8, humor: 0.3, energy: 0.5, depth: 0.2),
  ),
  reflective(
    'Thoughtful guide',
    'Patient conversation with space for meaning.',
    PersonaProfile(
        warmth: 0.8, directness: 0.4, humor: 0.3, energy: 0.3, depth: 0.9),
  );

  const NeuraPersonaPreset(this.label, this.description, this.profile);

  final String label;
  final String description;
  final PersonaProfile profile;

  bool matches(PersonaProfile other) =>
      profile.toMap().entries.every((e) => other.toMap()[e.key] == e.value);
}

/// Handwritten examples for an unsaved draft; no model, memory or audio access.
String personaStylePreview(PersonaProfile profile) {
  final greeting = profile.energy >= 0.7
      ? 'Hey! Ready to get into something?'
      : profile.energy <= 0.3
          ? 'Hi. We can take this at your pace.'
          : 'Hi. What would be useful today?';
  final support = profile.directness >= 0.7
      ? 'Pick one small thing to start with.'
      : profile.warmth >= 0.7
          ? 'We can work through one small thing together.'
          : 'A small first step can help.';
  final extra = profile.depth >= 0.7
      ? 'We can also explore why it matters to you.'
      : profile.humor >= 0.7
          ? 'No need to conquer the whole mountain before lunch.'
          : '';
  return [greeting, support, extra].where((s) => s.isNotEmpty).join(' ');
}
