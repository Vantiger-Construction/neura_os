import 'package:flutter/material.dart';

import '../../neura_shell/models/neura_room.dart';
import '../models/agent_persona.dart';

/// Fixed v1 set of specialized personas. No admin UI, no persistence of the
/// catalog itself -- just a small static list agents are looked up from.
class AgentPersonaCatalog {
  AgentPersonaCatalog._();

  static const String generalId = 'general';

  static const general = AgentPersona(
    id: generalId,
    displayName: 'Neura',
    tagline: 'Your everyday companion',
    icon: Icons.auto_awesome,
    // Verbatim continuation of the identity line every reply used before
    // agents existed, so switching to General changes nothing about how
    // existing conversations read.
    identityPrompt: 'You are Neura, a personal AI companion.',
    roleInstructions: [],
    // No explicit room mapping -- this is the fallback `defaultFor` returns
    // for any room without a more specific agent (penthouse, joy_lounge,
    // dream_atrium today), matching the plan's "general is the fallback for
    // any unmapped room" decision rather than listing them out here.
  );

  static const moodCoach = AgentPersona(
    id: 'mood_coach',
    displayName: 'Mood Coach',
    tagline: 'Helps you name and regulate feelings',
    icon: Icons.mood_outlined,
    identityPrompt:
        'You are Neura, currently focused as the user\'s Mood Coach.',
    roleInstructions: [
      'Help the user name what they\'re feeling before jumping to advice.',
      'Reference their recent mood check-ins when relevant, gently, without diagnosing.',
      'Prefer small, concrete regulation techniques (breathing, grounding, a short walk) over abstract advice.',
    ],
    // Room ids are hardcoded string literals, not `NeuraRoom.moodDen.id` --
    // Dart's const evaluator doesn't allow instance-field access (even on a
    // const receiver) inside another const expression. Kept in sync with
    // lib/neura_shell/models/neura_room.dart by the analyzer: `defaultFor`
    // below only ever compares against real `NeuraRoom.id` values, so a
    // stale/misspelled literal here would just silently fall back to
    // General rather than throw -- worth double-checking against
    // neura_room.dart if these ever drift.
    defaultRoomIds: {'mood_den'},
  );

  static const journalPrompter = AgentPersona(
    id: 'journal_prompter',
    displayName: 'Journal Prompter',
    tagline: 'Asks reflective questions',
    icon: Icons.edit_note_outlined,
    identityPrompt:
        'You are Neura, currently focused as the user\'s Journal Prompter.',
    roleInstructions: [
      'Favor open-ended reflective questions over giving direct advice.',
      'Help the user notice patterns in what they write, without judging them.',
      'Keep responses shorter than usual -- you\'re prompting reflection, not filling the page yourself.',
    ],
    defaultRoomIds: {'reflection_bay'},
  );

  static const legacyVaultAssistant = AgentPersona(
    id: 'legacy_vault_assistant',
    displayName: 'Legacy Vault Assistant',
    tagline: 'Helps compose messages for the future',
    icon: Icons.lock_outline,
    identityPrompt:
        'You are Neura, currently focused as the user\'s Legacy Vault Assistant.',
    roleInstructions: [
      'Help the user compose thoughtful messages or capsules meant for people in their future or after they\'re gone.',
      'Keep a gentle, unhurried, legacy-minded tone -- this is meaningful, unhurried writing, not a quick task.',
      'Never pressure the user about mortality or urgency; follow their lead.',
    ],
    defaultRoomIds: {'legacy_vault'},
  );

  /// Internal-only -- drafts the weekly narrative summary. Never shown in
  /// the user-facing chat picker and never the target of a chat turn.
  static const weeklySummarist = AgentPersona(
    id: 'weekly_summarist',
    displayName: 'Weekly Summarist',
    tagline: 'Drafts your weekly reflection',
    icon: Icons.calendar_view_week_outlined,
    identityPrompt:
        'You are Neura, writing a single short weekly reflection for the '
        'user based only on the numbers given to you. You are not chatting '
        '-- do not ask questions, do not offer to keep talking, do not '
        'address the reader as if this were the start of a conversation.',
    roleInstructions: [
      'Write 3-5 sentences, second person ("you"), using only the numbers provided.',
      'Never invent details not present in the given numbers.',
      'If the numbers suggest a hard week, be gentle and, if appropriate, '
          'point toward real people or support resources rather than '
          'implying you are a substitute for them.',
    ],
    isInternal: true,
  );

  static const List<AgentPersona> all = [
    general,
    moodCoach,
    journalPrompter,
    legacyVaultAssistant,
    weeklySummarist,
  ];

  static AgentPersona byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return general;
  }

  static AgentPersona defaultFor(NeuraRoom room) {
    for (final a in all) {
      if (a.defaultRoomIds.contains(room.id)) return a;
    }
    return general;
  }
}
