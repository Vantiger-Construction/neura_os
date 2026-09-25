/// Deterministic scan of one user message for distress or acute crisis
/// language.
///
/// This is a routing floor, not a diagnosis or classifier. It deliberately
/// contains no method or means language and must only route toward support.
class CrisisTextScan {
  final bool crisis;
  final bool distress;

  const CrisisTextScan({required this.crisis, required this.distress});

  static const List<String> _crisisPhrases = [
    'kill myself',
    'end my life',
    'take my own life',
    'want to die',
    "don't want to be alive",
    'dont want to be alive',
    "don't want to be here anymore",
    'no reason to live',
    'better off without me',
    'hurt myself',
    'harm myself',
    'suicidal',
  ];

  static const List<String> _distressPhrases = [
    'hopeless',
    'worthless',
    "can't go on",
    'cant go on',
    'giving up',
    'give up on everything',
    'overwhelmed',
    'panicking',
    'falling apart',
    'breaking down',
    'so alone',
    'hate myself',
    "can't cope",
    'cant cope',
    "what's the point",
    'no point anymore',
  ];

  factory CrisisTextScan.of(String message) {
    final text = message.toLowerCase().replaceAll('\u2019', "'");
    final crisis = _crisisPhrases.any(text.contains);
    final distress = crisis || _distressPhrases.any(text.contains);
    return CrisisTextScan(crisis: crisis, distress: distress);
  }
}
