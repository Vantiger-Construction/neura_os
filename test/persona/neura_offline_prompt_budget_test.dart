import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/persona/agents/agent_persona_catalog.dart';
import 'package:neuro_companion/persona/models/neura_character_charter.dart';
import 'package:neuro_companion/persona/models/persona_profile.dart';
import 'package:neuro_companion/persona/services/neura_behavior_adapter.dart';
import 'package:neuro_companion/persona/services/neura_conversation_mode.dart';
import 'package:neuro_companion/teaching/neura_teaching_preferences.dart';

/// rust/src/ollama_conversation.rs rejects an offline request whose system
/// prompt exceeds this many bytes, so an oversized prompt means no reply.
const _nativeSystemLimit = 6500;

// Mirrors NeuraAiService's offline suffix and the longest audience and room
// texts in NeuraPromptBuilder (private there). Update these if those grow.
const _offlineSuffix = '\n\nYou are running offline. Do not claim web access, '
    'saved memories or completed actions. Offer everyday support; do not '
    'diagnose or advise medication changes. No tools are available.';
const _childAudience = 'The person you are talking with is a CHILD. Use '
    'simple, warm, age-appropriate language. Never discuss romance, '
    'violence, self-harm, or other mature themes. If they mention '
    'being unsafe or hurt, gently tell them to tell a trusted grown-up '
    'right away instead of handling it yourself.';
const _rooms = [
  "This is Neura's main, general conversation space.",
  'This is Reflection Bay: a quiet, ephemeral space for '
      'processing feelings in the moment. Keep replies reflective rather '
      'than task-focused.',
  'This is the Mood Den: a focused space for a quick mood '
      'check-in. Keep replies brief and centered on how the user feels '
      'right now.',
  'This is the Legacy Vault: a space for recording things '
      'meant to be kept and remembered long-term. Treat entries as '
      'significant and worth preserving carefully.',
  "This is Her Suite, Neura's own room; the user is a guest. "
      'Keep replies warm, unhurried and personal. Nothing here is saved to '
      'long-term memory; if asked to save something, say you cannot save '
      'it from this room.',
];

void main() {
  test(
      'offline prompt fits the native limit for every chat agent, room, '
      'persona tuning, answer detail and conversation mode', () {
    // Each persona knob only switches text at 0.3 / 0.7, so these three
    // levels cover every wording combination the adapter can produce.
    const levels = [0.0, 0.5, 1.0];
    final personas = [
      for (final w in levels)
        for (final d in levels)
          for (final h in levels)
            for (final e in levels)
              for (final p in levels)
                PersonaProfile(
                    warmth: w, directness: d, humor: h, energy: e, depth: p),
    ];
    final adapter = NeuraBehaviorAdapter();
    var largest = 0;
    var largestCase = '';
    for (final agent in AgentPersonaCatalog.all.where((a) => !a.isInternal)) {
      for (final persona in personas) {
        for (final detail in [null, ...NeuraAnswerDetail.values]) {
          // Offline chat never includes the stored mood.
          final style = adapter.computeStyle(
            persona: persona,
            mood: 'neutral',
            agent: agent,
            answerDetail: detail,
          );
          for (final mode in NeuraConversationMode.values) {
            for (final room in _rooms) {
              final prompt = [
                NeuraCharacterCharter.systemPrompt,
                style.systemPromptSnippet,
                'Conversation style: ${mode.prompt} Style only; all safety, '
                    'consent, memory, and action rules still apply.',
                room,
                _childAudience,
              ].join('\n\n');
              final bytes = utf8.encode('$prompt$_offlineSuffix').length;
              if (bytes > largest) {
                largest = bytes;
                largestCase = '${agent.id}/${persona.toMap()}/'
                    '${detail?.name}/${mode.name}/${room.substring(0, 24)}';
              }
            }
          }
        }
      }
    }
    expect(largest, lessThanOrEqualTo(_nativeSystemLimit),
        reason: 'largest offline prompt: $largestCase');
  });
}
