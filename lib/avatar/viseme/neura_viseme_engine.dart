// lib/avatar/viseme/neura_viseme_engine.dart
//
// Heuristic viseme inference from text. Not phoneme-perfect, but stable and fast.
// Used to produce a believable "talking" mouth without relying on special TTS phoneme APIs.

import '../../core/neura_events_extra.dart';

class NeuraVisemeEngine {
  static final RegExp _vowel = RegExp(r'[aeiouy]', caseSensitive: false);
  static final RegExp _digit = RegExp(r'\d');

  /// Decide a viseme based on a small text fragment.
  /// This is intentionally simple: we want stable behavior and zero crash risk.
  static NeuraViseme inferFromFragment(String fragment) {
    if (fragment.isEmpty) return NeuraViseme.rest;

    final s = fragment.toLowerCase();

    // Numbers tend to sound punchy; treat as "AI".
    if (_digit.hasMatch(s)) return NeuraViseme.AI;

    // Common digraphs / consonant groups first.
    if (s.contains('th')) return NeuraViseme.TH;
    if (s.contains('sh') || s.contains('ch') || s.contains('j'))
      return NeuraViseme.CHJSH;
    if (s.contains('f') || s.contains('v')) return NeuraViseme.FV;
    if (s.contains('w') || s.contains('q')) return NeuraViseme.WQ;
    if (s.contains('m') || s.contains('b') || s.contains('p'))
      return NeuraViseme.MBP;
    if (s.contains('k') || s.contains('g') || s.contains('c'))
      return NeuraViseme.KG;
    if (s.contains('l')) return NeuraViseme.L;
    if (s.contains('r')) return NeuraViseme.R;
    if (s.contains('s') || s.contains('z') || s.contains('n'))
      return NeuraViseme.SZN;

    // Vowel shaping.
    if (s.contains('oo') || s.contains('ou') || s.contains('u'))
      return NeuraViseme.U;
    if (s.contains('ee') || s.contains('e')) return NeuraViseme.E;
    if (s.contains('ai') || s.contains('ay') || s.contains('a'))
      return NeuraViseme.AI;
    if (s.contains('i')) return NeuraViseme.I;
    if (s.contains('o')) return NeuraViseme.O;

    // Anything else: mild open mouth.
    if (_vowel.hasMatch(s)) return NeuraViseme.AI;
    return NeuraViseme.rest;
  }

  /// A cheap "mouth openness" guess based on character class.
  /// 0..1
  static double mouthOpenFromFragment(String fragment) {
    if (fragment.isEmpty) return 0.0;
    final s = fragment.toLowerCase();

    if (s.contains('oo') || s.contains('ou') || s.contains('u')) return 0.35;
    if (s.contains('ee') || s.contains('e')) return 0.25;
    if (s.contains('a')) return 0.55;
    if (s.contains('i')) return 0.35;
    if (s.contains('o')) return 0.45;
    if (s.contains('m') || s.contains('b') || s.contains('p'))
      return 0.10; // closed lips
    if (s.contains('f') || s.contains('v')) return 0.20;
    if (s.contains('s') || s.contains('z')) return 0.15;
    if (s.contains('th')) return 0.30;

    return 0.18;
  }
}
