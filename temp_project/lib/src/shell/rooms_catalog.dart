import 'package:flutter/material.dart';

import '../../modules/chat/neura_chat_screen.dart';
import '../../modules/coach/coach_settings_screen.dart';
import '../../modules/diagnostics/diagnostics_screen.dart';
import '../../modules/human/accessibility_screen.dart';
import '../../modules/human/life_snapshot_screen.dart';
import '../../modules/human/persona_lab_screen.dart';
import '../../modules/human/theme_screen.dart';
import '../../modules/human/two_minute_rescue_screen.dart';
import '../../modules/mood/mood_checkin_screen.dart';
import '../../modules/mood/mood_history_screen.dart';
import '../../modules/pay_it_forward/pay_it_forward_screen.dart';
import '../../modules/quests/quest_mode_screen.dart';
import '../../modules/review/weekly_review_screen.dart';
import '../../modules/support/support_center_screen.dart';
import '../../modules/timeline/life_timeline_screen.dart';
import '../../modules/vault/memory_vault_screen.dart';
import '../../screens/dream_journal_calendar_screen.dart';
import '../../screens/dream_show_screen.dart';
import '../../screens/dream_visualizer_screen.dart';
import '../../screens/journal_prompt_screen.dart';
import '../../screens/voice_journal_screen.dart';
import '../modules/focus/focus_office_screen.dart';
import '../modules/legacy/legacy_home_screen.dart';
import '../modules/settings/settings.dart';
import '../modules/voice/voice_lab_screen.dart';

enum RoomCategory {
  core,
  mood,
  journal,
  dreams,
  legacy,
  tools,
}

class RoomItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final RoomCategory category;
  final WidgetBuilder builder;

  RoomItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
    required this.builder,
  });
}

class RoomsCatalog {
  static List<RoomItem> all() => [
        RoomItem(
          id: 'chat',
          title: 'Neura (Chat)',
          subtitle: 'Plan, reflect, reset.',
          icon: Icons.chat_bubble_outline,
          category: RoomCategory.core,
          builder: (_) => NeuraChatScreen(),
        ),
        RoomItem(
          id: 'two_minute_rescue',
          title: 'Two‑Minute Rescue',
          subtitle: 'Micro-actions to stop the spiral.',
          icon: Icons.timer_outlined,
          category: RoomCategory.core,
          builder: (_) => TwoMinuteRescueScreen(),
        ),
        RoomItem(
          id: 'pay_it_forward',
          title: 'Pay It Forward',
          subtitle: 'Log kindness + build a goodwill streak.',
          icon: Icons.volunteer_activism,
          category: RoomCategory.core,
          builder: (_) => PayItForwardScreen(),
        ),
        RoomItem(
          id: 'life_snapshot',
          title: 'Life Snapshot',
          subtitle: 'Your last 7 days at a glance.',
          icon: Icons.analytics_outlined,
          category: RoomCategory.mood,
          builder: (_) => LifeSnapshotScreen(),
        ),
        RoomItem(
          id: 'life_timeline',
          title: 'Life Timeline',
          subtitle: 'Moods, quests, kindness, and reviews—one feed.',
          icon: Icons.timeline,
          category: RoomCategory.tools,
          builder: (_) => LifeTimelineScreen(),
        ),
        RoomItem(
          id: 'quest_mode',
          title: 'Quest Mode',
          subtitle: 'Tiny missions. Real momentum.',
          icon: Icons.emoji_events_outlined,
          category: RoomCategory.core,
          builder: (_) => QuestModeScreen(),
        ),
        RoomItem(
          id: 'weekly_review',
          title: 'Weekly Review',
          subtitle: 'Auto-summarize your week (kindly).',
          icon: Icons.event_note_outlined,
          category: RoomCategory.core,
          builder: (_) => WeeklyReviewScreen(),
        ),
        RoomItem(
          id: 'support_center',
          title: 'Support Center',
          subtitle: 'Calm protocols + trusted contacts.',
          icon: Icons.health_and_safety_outlined,
          category: RoomCategory.core,
          builder: (_) => SupportCenterScreen(),
        ),
        RoomItem(
          id: 'memory_vault',
          title: 'Memory Vault',
          subtitle: 'Private notes + exports + delete.',
          icon: Icons.lock_outline,
          category: RoomCategory.tools,
          builder: (_) => MemoryVaultScreen(),
        ),
        RoomItem(
          id: 'focus',
          title: 'Focus Office',
          subtitle: 'Set the vibe: deep work, reflection, wind down.',
          icon: Icons.psychology_alt_outlined,
          category: RoomCategory.core,
          builder: (_) => FocusOfficeScreen(),
        ),
        RoomItem(
          id: 'mood_checkin',
          title: 'Mood Check‑In',
          subtitle: 'Quick emotional snapshot.',
          icon: Icons.favorite_border,
          category: RoomCategory.mood,
          builder: (_) => MoodCheckInScreen(),
        ),
        RoomItem(
          id: 'mood_history',
          title: 'Mood History',
          subtitle: 'Trends over time.',
          icon: Icons.timeline,
          category: RoomCategory.mood,
          builder: (_) => MoodHistoryScreen(),
        ),
        RoomItem(
          id: 'journal_prompt',
          title: 'Journal Prompt',
          subtitle: 'Time-aware prompt.',
          icon: Icons.edit_note,
          category: RoomCategory.journal,
          builder: (_) => JournalPromptScreen(),
        ),
        RoomItem(
          id: 'voice_journal',
          title: 'Voice Journal',
          subtitle: 'Speak it. Save it.',
          icon: Icons.mic_none,
          category: RoomCategory.journal,
          builder: (_) => VoiceJournalScreen(),
        ),
        RoomItem(
          id: 'dream_visualizer',
          title: 'Dream Visualizer',
          subtitle: 'Dream timeline and tags.',
          icon: Icons.auto_awesome,
          category: RoomCategory.dreams,
          builder: (_) => DreamVisualizerScreen(),
        ),
        RoomItem(
          id: 'dream_calendar',
          title: 'Dream Calendar',
          subtitle: 'Browse dreams by date.',
          icon: Icons.calendar_month_outlined,
          category: RoomCategory.dreams,
          builder: (_) => DreamJournalCalendarScreen(),
        ),
        RoomItem(
          id: 'dream_show',
          title: 'Monthly Dream Show',
          subtitle: 'Animated recap (prototype).',
          icon: Icons.movie_outlined,
          category: RoomCategory.dreams,
          builder: (_) => DreamShowScreen(),
        ),
        RoomItem(
          id: 'legacy',
          title: 'Legacy Vault',
          subtitle: 'Time capsules and messages.',
          icon: Icons.auto_stories,
          category: RoomCategory.legacy,
          builder: (_) => LegacyHomeScreen(),
        ),
        RoomItem(
          id: 'voice_lab',
          title: 'Voice Lab',
          subtitle: 'Test Neura voice + live mic visemes.',
          icon: Icons.record_voice_over_outlined,
          category: RoomCategory.tools,
          builder: (_) => VoiceLabScreen(),
        ),
        RoomItem(
          id: 'coach',
          title: 'Neura Coach',
          subtitle: 'Reflections + Coach Timeline.',
          icon: Icons.psychology_alt_outlined,
          category: RoomCategory.tools,
          builder: (_) => CoachSettingsScreen(),
        ),
        RoomItem(
          id: 'persona_lab',
          title: 'Persona Lab',
          subtitle: 'Tune Neura’s style for you.',
          icon: Icons.tune_outlined,
          category: RoomCategory.tools,
          builder: (_) => PersonaLabScreen(),
        ),
        RoomItem(
          id: 'accessibility',
          title: 'Accessibility',
          subtitle: 'Text size, motion, and comfort.',
          icon: Icons.accessibility_new_outlined,
          category: RoomCategory.tools,
          builder: (_) => AccessibilityScreen(),
        ),
        RoomItem(
          id: 'themes',
          title: 'Themes',
          subtitle: 'Theme mode + contrast.',
          icon: Icons.palette_outlined,
          category: RoomCategory.tools,
          builder: (_) => ThemeScreen(),
        ),
        RoomItem(
          id: 'settings',
          title: 'Settings',
          subtitle: 'Privacy, safety, and controls.',
          icon: Icons.settings_outlined,
          category: RoomCategory.tools,
          builder: (_) => SettingsScreen(),
        ),
        RoomItem(
          id: 'diagnostics',
          title: 'Diagnostics',
          subtitle: 'Logs + Dimensional Sync.',
          icon: Icons.bug_report_outlined,
          category: RoomCategory.tools,
          builder: (_) => DiagnosticsScreen(),
        ),
      ];
}
