import 'dart:convert';

/// How the other person is likely to react in a rehearsal.
enum NeuraRehearsalReaction { calm, guarded, upset }

extension NeuraRehearsalReactionLabel on NeuraRehearsalReaction {
  String get label => switch (this) {
        NeuraRehearsalReaction.calm => 'Open',
        NeuraRehearsalReaction.guarded => 'Guarded',
        NeuraRehearsalReaction.upset => 'Upset',
      };

  String get _direction => switch (this) {
        NeuraRehearsalReaction.calm =>
          'You are open and willing to listen, with ordinary questions.',
        NeuraRehearsalReaction.guarded =>
          'You are a little defensive at first: you deflect, ask why this is '
              'coming up now, or minimize it. You soften when they stay clear '
              'and kind.',
        NeuraRehearsalReaction.upset =>
          'You are hurt or frustrated and say so plainly, and you interrupt '
              'with your side. You calm down when you feel heard.',
      };
}

/// One practice conversation: Neura plays the other person so the user can
/// try out a hard talk, then steps out of the role to give gentle feedback.
///
/// Pure prompt and transcript shaping; the reply itself goes through
/// NeuraAiService, with the same guardrails as chat.
class NeuraRehearsal {
  NeuraRehearsal({
    required String who,
    required String goal,
    this.reaction = NeuraRehearsalReaction.guarded,
  })  : who = _clean(who, maxWhoLength),
        goal = _clean(goal, maxGoalLength) {
    if (this.who.isEmpty) throw ArgumentError('Say who the talk is with.');
    if (this.goal.isEmpty) throw ArgumentError('Say what you want to say.');
  }

  static const maxWhoLength = 60;
  static const maxGoalLength = 300;

  /// Practice turns by the user before feedback is suggested.
  static const maxTurns = 12;

  /// Transcript kept for the model, newest turns first to be kept.
  static const maxTranscriptBytes = 3500;

  final String who;
  final String goal;
  final NeuraRehearsalReaction reaction;

  static String _clean(String value, int max) {
    final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : flat.substring(0, max).trim();
  }

  /// Instructions for playing the other person.
  String get characterPrompt => '''
You are helping someone rehearse a difficult conversation. Play the other person: $who.
What they want to talk about: $goal
${reaction._direction}

Rules:
- Stay in character and speak only as $who, in one to three short spoken sentences. No narration, stage directions, lists or advice.
- Be realistic but never cruel: no insults, threats, slurs or contempt, and never mock them.
- Do not invent shocking facts or secrets about either person.
- If they seem truly distressed (not just practising), step out of the role, say "Let's pause the practice," and check on them kindly.''';

  /// Instructions for the feedback at the end, as Neura again.
  String feedbackPrompt(List<NeuraRehearsalLine> lines) => '''
You are Neura, a warm companion. The user just practised a hard conversation with $who, played by you. Their goal: $goal

Practice transcript:
${transcript(lines)}

Give brief, kind coaching in plain spoken sentences, no headings:
1. One thing they did well, quoting their own words if you can.
2. One thing to try next time, with an example phrasing they could use.
3. A short opening line they could start the real talk with.
Keep it under 120 words. Do not judge $who.''';

  /// The practice so far, newest lines kept within [maxTranscriptBytes].
  String transcript(List<NeuraRehearsalLine> lines) {
    final kept = <String>[];
    var bytes = 0;
    for (final line in lines.reversed) {
      final text = '${line.fromUser ? 'You' : who}: ${line.text}';
      final size = utf8.encode(text).length + 1;
      if (bytes + size > maxTranscriptBytes) break;
      kept.insert(0, text);
      bytes += size;
    }
    return kept.join('\n');
  }

  /// The practice as chat messages for the character model: the user speaks
  /// as themselves, the model's earlier lines are its own.
  List<Map<String, String>> characterMessages(List<NeuraRehearsalLine> lines) {
    final messages = <Map<String, String>>[];
    var bytes = 0;
    for (final line in lines.reversed) {
      final size = utf8.encode(line.text).length;
      if (bytes + size > maxTranscriptBytes) break;
      messages.insert(0, {
        'role': line.fromUser ? 'user' : 'assistant',
        'content': line.text,
      });
      bytes += size;
    }
    // A chat history must start with the user.
    while (messages.isNotEmpty && messages.first['role'] != 'user') {
      messages.removeAt(0);
    }
    return messages;
  }
}

class NeuraRehearsalLine {
  final bool fromUser;
  final String text;

  const NeuraRehearsalLine({required this.fromUser, required this.text});
}
