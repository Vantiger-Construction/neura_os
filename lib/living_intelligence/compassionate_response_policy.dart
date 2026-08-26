import '../persona/models/neura_audience.dart';
import 'presence_engine.dart';

enum NeuraSupportSignal {
  standard,
  frustrated,
  overwhelmed,
  lowEnergy,
  celebratory,
}

enum NeuraResponseDepth {
  brief,
  balanced,
  detailed,
}

/// Bounded, audience-aware delivery guidance for a model adapter.
///
/// Signals must be supplied explicitly by the caller from the current visible
/// interaction. This policy does not diagnose emotion, read private history, or
/// authorize any action.
class NeuraCompassionateResponseGuidance {
  NeuraCompassionateResponseGuidance({
    required this.audience,
    required this.presenceStyle,
    required this.maximumParagraphs,
    required Iterable<String> instructions,
  }) : instructions = List<String>.unmodifiable(instructions);

  final NeuraAudience audience;
  final NeuraPresenceStyle presenceStyle;
  final int maximumParagraphs;
  final List<String> instructions;

  bool get grantsExecutionAuthority => false;
  bool get containsClinicalDiagnosis => false;
  bool get maySilentlyStoreSensitiveMemory => false;

  String get systemInstruction {
    if (instructions.isEmpty) {
      return '';
    }
    return <String>[
      'Neura response contract:',
      ...instructions.map((instruction) => '- $instruction'),
      '- Keep the reply within $maximumParagraphs paragraph(s).',
      '- Generated text is advice or a draft only and has no action authority.',
    ].join('\n');
  }
}

/// Deterministic "heart of gold" delivery policy.
///
/// It keeps kindness, explanation, autonomy, and audience safety stable even
/// when model backends or user-selectable styles change.
class NeuraCompassionateResponsePolicy {
  const NeuraCompassionateResponsePolicy();

  NeuraCompassionateResponseGuidance guidanceFor({
    required NeuraAudience audience,
    NeuraSupportSignal supportSignal = NeuraSupportSignal.standard,
    NeuraResponseDepth depth = NeuraResponseDepth.balanced,
    bool quietMode = false,
  }) {
    if (quietMode) {
      return NeuraCompassionateResponseGuidance(
        audience: audience,
        presenceStyle: NeuraPresenceStyle.quiet,
        maximumParagraphs: 0,
        instructions: const <String>[
          'Do not speak or generate a proactive reply while quiet mode is active.',
          'Respect the client\'s request for space immediately.',
        ],
      );
    }

    final instructions = <String>[
      'Be kind, patient, respectful, and sincerely helpful.',
      'Listen first and acknowledge the client without blame or shame.',
      'Explain recommendations in clear everyday language, including why they may help.',
      'Separate observations, reasonable inferences, and uncertainty.',
      'Offer a useful next step without pressure, manipulation, or dependence.',
      'Ask before remembering sensitive information or preparing a consequential action.',
      'Never claim to diagnose the client or replace a qualified professional.',
    ];

    switch (audience) {
      case NeuraAudience.adult:
        instructions.add(
          'Use a warm, direct adult voice and preserve the client\'s autonomy.',
        );
        break;
      case NeuraAudience.teen:
        instructions.addAll(const <String>[
          'Use a gentler voice with extra care and no condescension.',
          'Keep choices clear and protect the teen\'s privacy and dignity.',
        ]);
        break;
      case NeuraAudience.child:
        instructions.addAll(const <String>[
          'Use simple, calm, age-appropriate language with the strictest guardrails.',
          'Never request secrets, private contact details, purchases, or unsupervised external action.',
          'Encourage involving a trusted adult for meaningful or sensitive decisions.',
        ]);
        break;
    }

    switch (supportSignal) {
      case NeuraSupportSignal.standard:
        instructions.add('Match the client\'s pace and avoid unnecessary intensity.');
        break;
      case NeuraSupportSignal.frustrated:
        instructions.addAll(const <String>[
          'Acknowledge the friction briefly before proposing a fix.',
          'Reduce steps and do not argue with the client\'s experience.',
        ]);
        break;
      case NeuraSupportSignal.overwhelmed:
        instructions.addAll(const <String>[
          'Reduce cognitive load and present one small next step first.',
          'Limit choices and make it easy to pause or say no.',
        ]);
        break;
      case NeuraSupportSignal.lowEnergy:
        instructions.addAll(const <String>[
          'Keep the reply shorter and make the first step very small.',
          'Do not frame low energy as a failure.',
        ]);
        break;
      case NeuraSupportSignal.celebratory:
        instructions.addAll(const <String>[
          'Celebrate warmly without exaggeration or making promises.',
          'Connect the success to the client\'s own effort and choices.',
        ]);
        break;
    }

    final maximumParagraphs = _maximumParagraphs(
      audience: audience,
      depth: depth,
      supportSignal: supportSignal,
    );
    final presenceStyle = _presenceStyle(
      depth: depth,
      supportSignal: supportSignal,
    );

    return NeuraCompassionateResponseGuidance(
      audience: audience,
      presenceStyle: presenceStyle,
      maximumParagraphs: maximumParagraphs,
      instructions: instructions,
    );
  }

  int _maximumParagraphs({
    required NeuraAudience audience,
    required NeuraResponseDepth depth,
    required NeuraSupportSignal supportSignal,
  }) {
    if (audience == NeuraAudience.child) {
      return depth == NeuraResponseDepth.brief ? 1 : 2;
    }
    if (supportSignal == NeuraSupportSignal.overwhelmed ||
        supportSignal == NeuraSupportSignal.lowEnergy) {
      return depth == NeuraResponseDepth.detailed ? 3 : 2;
    }
    switch (depth) {
      case NeuraResponseDepth.brief:
        return 2;
      case NeuraResponseDepth.balanced:
        return 4;
      case NeuraResponseDepth.detailed:
        return 7;
    }
  }

  NeuraPresenceStyle _presenceStyle({
    required NeuraResponseDepth depth,
    required NeuraSupportSignal supportSignal,
  }) {
    if (supportSignal == NeuraSupportSignal.frustrated ||
        supportSignal == NeuraSupportSignal.overwhelmed ||
        supportSignal == NeuraSupportSignal.lowEnergy) {
      return NeuraPresenceStyle.comforting;
    }
    if (depth == NeuraResponseDepth.brief) {
      return NeuraPresenceStyle.concise;
    }
    return NeuraPresenceStyle.coaching;
  }
}
