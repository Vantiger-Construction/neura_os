import 'package:flutter/material.dart';

import '../../notifications/notifications_settings_screen.dart';
import '../../screens/dream_journal_calendar_screen.dart';
import '../../screens/help_screen.dart';
import '../../screens/journal_prompt_screen.dart';
import '../../screens/neura_voice_settings_screen.dart';
import '../../services/neura_voice_command.dart';
import '../../src/modules/focus/focus_office_screen.dart';
import '../../src/modules/privacy/privacy_home_screen.dart';
import '../../src/modules/settings/settings.dart';
import '../human/accessibility_screen.dart';
import '../human/theme_screen.dart';
import '../mood/mood_checkin_screen.dart';
import '../mood/mood_history_screen.dart';
import '../quests/quest_mode_screen.dart';
import '../review/weekly_review_screen.dart';
import '../support/guided_support_screen.dart';
import '../timeline/life_timeline_screen.dart';

typedef NeuraVoiceDestination = ({String name, WidgetBuilder builder});

/// These destinations only open existing UI. Saving, generating, exporting,
/// and enabling optional features still require their normal on-screen action.
NeuraVoiceDestination? neuraVoiceDestination(NeuraVoiceCommand command) =>
    switch (command) {
      NeuraVoiceCommand.guidedSupport => (
          name: '/care/guided-support',
          builder: (_) => const GuidedSupportScreen()
        ),
      NeuraVoiceCommand.openJournal => (
          name: '/memory/journal-prompt',
          builder: (_) => const JournalPromptScreen()
        ),
      NeuraVoiceCommand.openMood => (
          name: '/care/mood-check-in',
          builder: (_) => const MoodCheckInScreen()
        ),
      NeuraVoiceCommand.openMoodHistory => (
          name: '/care/mood-history',
          builder: (_) => const MoodHistoryScreen()
        ),
      NeuraVoiceCommand.openWeeklyReview => (
          name: '/memory/weekly-review',
          builder: (_) => const WeeklyReviewScreen()
        ),
      NeuraVoiceCommand.openDreamJournal => (
          name: '/memory/dream-calendar',
          builder: (_) => const DreamJournalCalendarScreen()
        ),
      NeuraVoiceCommand.openFocus => (
          name: '/settings/focus',
          builder: (_) => const FocusOfficeScreen()
        ),
      NeuraVoiceCommand.openQuests => (
          name: '/spaces/quests',
          builder: (_) => const QuestModeScreen()
        ),
      NeuraVoiceCommand.openTimeline => (
          name: '/memory/timeline',
          builder: (_) => const LifeTimelineScreen()
        ),
      NeuraVoiceCommand.openSettings => (
          name: '/settings',
          builder: (_) => const SettingsScreen()
        ),
      NeuraVoiceCommand.openVoiceSettings => (
          name: '/settings/voice',
          builder: (_) => const NeuraVoiceSettingsScreen()
        ),
      NeuraVoiceCommand.openAccessibility => (
          name: '/settings/accessibility',
          builder: (_) => const AccessibilityScreen()
        ),
      NeuraVoiceCommand.openThemes => (
          name: '/settings/themes',
          builder: (_) => const ThemeScreen()
        ),
      NeuraVoiceCommand.openPrivacy => (
          name: '/settings/privacy',
          builder: (_) => const PrivacyHomeScreen()
        ),
      NeuraVoiceCommand.openNotifications => (
          name: '/settings/notifications',
          builder: (_) => const NotificationsSettingsScreen()
        ),
      NeuraVoiceCommand.openHelp => (
          name: '/settings/help',
          builder: (_) => const HelpScreen()
        ),
      _ => null,
    };
