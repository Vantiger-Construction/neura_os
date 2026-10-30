import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/supabase_config.dart';
import '../../neura_shell/neura_shell.dart';
import '../../neura_shell/neura_shell_state.dart';
import '../../neura_shell/models/neura_room.dart';
import '../../services/ambient_listening_prefs.dart';
import '../../services/auth_service.dart';
import '../../services/neura_companion_presence.dart';
import '../../services/update_check_service.dart';
import '../../services/wake_word_prefs.dart';
import '../../avatar/neura_avatar_runtime_bridge.dart';
import '../../src/shell/shell_prefs.dart';

import '../../care/screens/neura_care_loop_screen.dart';
import '../../dreams/screens/dream_show2_screen.dart';
import '../../insights/screens/weekly_snapshot_screen.dart';
import '../../modules/humor/joke_screen.dart';
import '../../modules/money/money_manager_screen.dart';
import '../../modules/therapy/therapy_path_screen.dart';
import '../../modules/mood/mood_checkin_screen.dart';
import '../../modules/mood/mood_history_screen.dart';
import '../../modules/pay_it_forward/pay_it_forward_screen.dart';
import '../../modules/quests/quest_mode_screen.dart';
import '../../modules/support/support_center_screen.dart';
import '../../modules/timeline/life_timeline_screen.dart';
import '../../modules/vault/memory_vault_screen.dart';
import '../../os_shell/screens/os_shell_home_screen.dart';
import '../review/weekly_review_screen.dart';
import '../../screens/dream_journal_calendar_screen.dart';
import '../../screens/monthly_dream_show_screen.dart';
import '../../screens/dream_visualizer_screen.dart';
import '../../screens/journal_prompt_screen.dart';
import '../../screens/voice_journal_screen.dart';
import '../../adaptive_intent/neura_live_signal_adapter.dart';
import '../../dashboard/widgets/proactive_banner_card.dart';
import '../../intelligence/intelligence_center_screen.dart';
import '../../living_intelligence/decision_path_screen.dart';
import '../../living_intelligence/trusted_devices_screen.dart';
import '../../insights/services/weekly_summarist_service.dart';
import '../../notifications/neura_notifications_prefs.dart';
import '../../notifications/neura_notifications_service.dart';
import '../../reliability/safe_boot.dart';
import '../../services/ambient_listening_service.dart';
import '../../services/wake_word_listener_service.dart';
import '../../src/modules/legacy/legacy_deadman_service.dart';
import '../../widgets/ambient_recording_badge.dart';
import '../../src/modules/legacy/legacy_home_screen.dart';
import '../../src/modules/settings/settings.dart';
import '../chat/neura_chat_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import 'presence_navigation_shell.dart';
import '../camera_hawk/camera_hawk_screen.dart';

class EnhancedNavigation extends StatefulWidget {
  const EnhancedNavigation({super.key});

  @override
  State<EnhancedNavigation> createState() => _EnhancedNavigationState();
}

class _EnhancedNavigationState extends State<EnhancedNavigation> {
  static const List<Widget> _destinationPages = <Widget>[
    SizedBox.shrink(),
    OsShellHomeScreen(),
    NeuraCareLoopScreen(),
    _MemoryHub(),
    SettingsScreen(),
  ];

  int _index = 0;
  NeuraShellState? _shellState;
  bool _avatarDocked = false;
  Stream<dynamic>? _authStateChanges;
  late final List<PresenceCommand> _commandCatalog;

  bool get _optionalHooksAllowed => !SafeBoot.instance.safeMode.value;

  @override
  void initState() {
    super.initState();
    _commandCatalog = _buildCommandCatalog();
    NeuraCompanionPresence.instance.state.addListener(_publishAvatarState);
    ShellPrefsController.instance.prefs.addListener(_publishAvatarState);
    // Legacy Guard (dead-man's-switch) can be enabled from Legacy Vault ->
    // Legacy Guard; this is the startup check that actually detects an
    // overdue check-in and offers to release capsules. No-ops if disabled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_optionalHooksAllowed) return;
      unawaited(LegacyDeadmanService.instance.maybePromptOnStartup(context));
    });

    // Safe Mode deliberately avoids optional native, network, and proactive
    // work. Startup already suppresses these services; keep the dashboard's
    // post-boot hooks from silently starting them again after navigation.
    if (!_optionalHooksAllowed) return;

    // Speaks a short greeting once per launch, then -- only if the user has
    // opted in under Settings > Privacy & Safety -- starts voice-activated
    // ambient listening. No BuildContext needed past this point; the
    // service only speaks (once) and writes encrypted files to disk.
    //
    // Deliberately delayed a couple seconds past the first frame (not fired
    // from the immediate postFrameCallback like the other hooks here): this
    // is the app's first-ever *proactive* native TTS call, immediately
    // followed by starting mic capture -- two native audio subsystems
    // (SAPI/WinRT speech synthesis, then WASAPI capture) initializing back
    // to back, this early in the window's lifecycle, is a combination that
    // has never been exercised before today. Giving the window/engine a
    // moment to fully settle after first paint avoids finding out the hard
    // way whether that combination is safe at the literal first frame.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || !_optionalHooksAllowed) return;
      unawaited(AmbientListeningService.instance.greetAndStartListening());
      // Same "let the window/engine settle first" reasoning as the greeting
      // above -- this is also a native voice subsystem starting for the
      // first time. Opt-in and off by default; start() itself checks the
      // pref and no-ops if the user hasn't enabled it.
      unawaited(WakeWordListenerService.instance.start());
    });
    // Cadence-gated, at most once per week -- see WeeklySummaristService's
    // doc comment for why this is the right (and only reasonable) place to
    // fire it. No BuildContext needed: it only writes to prefs, never shows
    // UI itself.
    unawaited(_generateWeeklySummaryThenMaybeNotify());
    unawaited(_maybeNotifyLegacyOverdue());
    unawaited(_reconfirmDailyMoodNudgeSchedule());
    unawaited(_checkForUpdate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NeuraShell.of(context);
    if (identical(_shellState, shell)) return;
    final previous = _shellState;
    if (_avatarDocked && previous != null) {
      unawaited(previous.setAvatarDockedInApp(false));
    }
    previous?.removeListener(_publishAvatarState);
    _shellState = shell;
    shell.addListener(_publishAvatarState);
    _avatarDocked = true;
    unawaited(shell.setAvatarDockedInApp(true));
    _publishAvatarState();
  }

  @override
  void dispose() {
    final shell = _shellState;
    shell?.removeListener(_publishAvatarState);
    NeuraCompanionPresence.instance.state.removeListener(_publishAvatarState);
    ShellPrefsController.instance.prefs.removeListener(_publishAvatarState);
    if (_avatarDocked && shell != null) {
      unawaited(shell.setAvatarDockedInApp(false));
    }
    super.dispose();
  }

  void _publishAvatarState() {
    final shell = _shellState;
    if (shell == null) return;
    NeuraAvatarRuntimeBridge.instance.publish(
      room: shell.room,
      phase: NeuraCompanionPresence.instance.state.value.phase,
      preferences: ShellPrefsController.instance.prefs.value,
    );
  }

  /// Wraps WeeklySummaristService's own app-open hook so a notification can
  /// fire right after a *fresh* generation -- checks freshness after, rather
  /// than threading a callback through the existing service, so this stays
  /// purely additive to it.
  Future<void> _generateWeeklySummaryThenMaybeNotify() async {
    if (!_optionalHooksAllowed) return;
    await WeeklySummaristService.instance.maybeGenerateOnAppOpen();
    if (!_optionalHooksAllowed) return;
    if (!NeuraNotificationsPrefsController
        .instance.prefs.value.weeklyReviewReadyEnabled) {
      return;
    }
    final fresh = await WeeklySummaristService.instance.currentIfFresh();
    if (fresh == null) return;
    if (DateTime.now().difference(fresh.generatedAt) >
        const Duration(minutes: 1)) {
      return;
    }
    if (!_optionalHooksAllowed) return;
    await NeuraNotificationsService.instance
        .showWeeklyReviewReadyNotification();
  }

  Future<void> _maybeNotifyLegacyOverdue() async {
    if (!_optionalHooksAllowed) return;
    if (!NeuraNotificationsPrefsController
        .instance.prefs.value.legacyOverdueEnabled) {
      return;
    }
    final overdue = await LegacyDeadmanService.instance.isOverdue();
    if (!overdue || !_optionalHooksAllowed) return;
    await NeuraNotificationsService.instance.showLegacyOverdueNotification();
  }

  /// Windows' own notification platform keeps a daily-repeating scheduled
  /// toast alive across app restarts once scheduled, but re-asserting it on
  /// every app open is cheap and guards against it having been lost (e.g.
  /// after a rebuild/reinstall).
  Future<void> _reconfirmDailyMoodNudgeSchedule() async {
    if (!_optionalHooksAllowed) return;
    final prefs = NeuraNotificationsPrefsController.instance.prefs.value;
    if (!prefs.dailyMoodNudgeEnabled) return;
    await NeuraNotificationsService.instance.scheduleDailyMoodNudge(
      TimeOfDay(
        hour: prefs.dailyMoodNudgeHour,
        minute: prefs.dailyMoodNudgeMinute,
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    if (!_optionalHooksAllowed) return;
    final update = await UpdateCheckService.instance.checkForUpdate();
    if (update == null || !mounted || !_optionalHooksAllowed) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text(
          'Neura ${update.tag} is available - you\'re on an older build.',
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(update.htmlUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('View'),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _openChat() {
    _openRoute('/chat', (_) => const NeuraChatScreen());
  }

  void _openDiagnostics() {
    _openRoute('/diagnostics', (_) => const DiagnosticsScreen());
  }

  void _openRoute(String routeName, WidgetBuilder builder, {NeuraRoom? room}) {
    final shell = _shellState;
    if (room != null && shell != null && shell.isLoaded) {
      unawaited(shell.setRoom(room));
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: builder,
        settings: RouteSettings(name: routeName),
      ),
    );
  }

  void _onTab(int i) {
    NeuraAdaptiveActivityTracker.instance.recordSurfaceVisit('primary_tab_$i');
    if (_index != i) setState(() => _index = i);

    // Optional magic: sync rooms to tabs, so the OS "moves" with you.
    final shell = _shellState ?? NeuraShell.of(context);
    if (!shell.isLoaded) return;
    if (shell.autoRoomSync) {
      unawaited(shell.setRoom(_roomForIndex(i)));
    }
  }

  NeuraRoom _roomForIndex(int i) {
    switch (i) {
      case 0:
        return NeuraRoom.penthouse;
      case 1:
        return NeuraRoom.penthouse;
      case 2:
        return NeuraRoom.moodDen;
      case 3:
        return NeuraRoom.reflectionBay;
      case 4:
        return NeuraRoom.moodDen;
      default:
        return NeuraRoom.penthouse;
    }
  }

  PresenceShellStatus _presenceStatus() {
    final safeMode = SafeBoot.instance.safeMode.value;
    final presence = NeuraCompanionPresence.instance.state.value;
    final voiceOptedIn =
        AmbientListeningPrefsController.instance.enabled.value ||
            WakeWordPrefsController.instance.enabled.value;
    final voiceLabel = switch (presence.phase) {
      NeuraPresencePhase.listening when !safeMode => 'Listening locally',
      NeuraPresencePhase.speaking when !safeMode => 'Speaking locally',
      _ when safeMode => 'Voice off',
      _ when voiceOptedIn => 'Voice ready',
      _ => 'Voice off',
    };
    final cloudReady = !safeMode &&
        SupabaseConfig.isConfigured &&
        AuthService.isAvailable &&
        AuthService.currentUser != null;

    return PresenceShellStatus(
      safeMode: safeMode,
      cloudLabel: safeMode
          ? 'Cloud blocked'
          : cloudReady
              ? 'Cloud gated'
              : 'Local only',
      voiceLabel: voiceLabel,
      presenceLabel: presence.label,
      phase: presence.phase,
    );
  }

  List<PresenceCommand> _buildCommandCatalog() => <PresenceCommand>[
        PresenceCommand(
          id: 'camera-hawk',
          title: 'Camera Hawk',
          subtitle: 'Your private camera center on this Windows PC.',
          icon: Icons.videocam_outlined,
          keywords: const <String>['camera', 'security', 'hawk', 'nvr'],
          onSelected: () =>
              _openRoute('/camera-hawk', (_) => const CameraHawkScreen()),
        ),
        PresenceCommand(
          id: 'talk',
          title: 'Talk to Neura',
          subtitle: 'Plan, reflect, or reset with Neura.',
          icon: Icons.chat_bubble_outline,
          keywords: const <String>['chat', 'companion', 'assistant'],
          onSelected: _openChat,
        ),
        PresenceCommand(
          id: 'care-loop',
          title: 'Neura Care Loop',
          subtitle: 'Notice, steady, and choose one next step.',
          icon: Icons.spa_outlined,
          keywords: const <String>['care', 'grounding', 'wellbeing'],
          pinned: true,
          onSelected: () => _onTab(2),
        ),
        PresenceCommand(
          id: 'journal-prompt',
          title: 'Journal Prompt',
          subtitle: 'Write privately with a time-aware prompt.',
          icon: Icons.edit_note,
          keywords: const <String>['journal', 'write', 'reflection'],
          pinned: true,
          onSelected: () => _openRoute(
            '/memory/journal-prompt',
            (_) => JournalPromptScreen(),
            room: NeuraRoom.reflectionBay,
          ),
        ),
        PresenceCommand(
          id: 'mood-check-in',
          title: 'Mood Check-In',
          subtitle: 'Save a private emotional snapshot.',
          icon: Icons.favorite_border,
          keywords: const <String>['mood', 'feeling', 'check in'],
          pinned: true,
          onSelected: () => _openRoute(
            '/care/mood-check-in',
            (_) => const MoodCheckInScreen(),
            room: NeuraRoom.moodDen,
          ),
        ),
        PresenceCommand(
          id: 'rooms',
          title: 'Explore Spaces',
          subtitle: 'Reflection, Care, Dreams, Mirror, Persona, and Kids.',
          icon: Icons.holiday_village_outlined,
          keywords: const <String>['rooms', 'spaces', 'world'],
          pinned: true,
          onSelected: () => _onTab(1),
        ),
        PresenceCommand(
          id: 'intelligence',
          title: 'Neura Intelligence',
          subtitle: 'Signals, decision receipts, and consent controls.',
          icon: Icons.hub_outlined,
          keywords: const <String>['signals', 'consent', 'receipts'],
          onSelected: () => _openRoute(
            '/intelligence',
            (_) => const NeuraIntelligenceCenterScreen(),
          ),
        ),
        PresenceCommand(
          id: 'mood-history',
          title: 'Mood History',
          subtitle: 'Review your on-device emotional weather.',
          icon: Icons.timeline,
          keywords: const <String>['mood', 'history', 'trend'],
          onSelected: () => _openRoute(
              '/care/mood-history', (_) => const MoodHistoryScreen()),
        ),
        PresenceCommand(
          id: 'weekly-snapshot',
          title: 'Weekly Snapshot',
          subtitle: 'Mood trends, rituals, and export.',
          icon: Icons.insights,
          keywords: const <String>['week', 'trend', 'export'],
          onSelected: () => _openRoute(
            '/memory/weekly-snapshot',
            (_) => const WeeklySnapshotScreen(),
          ),
        ),
        PresenceCommand(
          id: 'weekly-review',
          title: 'Weekly Review',
          subtitle: 'Past weeks, notes, and coach commentary.',
          icon: Icons.auto_awesome_outlined,
          keywords: const <String>['week', 'review', 'coach'],
          onSelected: () => _openRoute(
            '/memory/weekly-review',
            (_) => const WeeklyReviewScreen(),
          ),
        ),
        PresenceCommand(
          id: 'voice-journal',
          title: 'Voice Journal',
          subtitle: 'Speak only after opening its visible recording UI.',
          icon: Icons.mic_none,
          keywords: const <String>['voice', 'journal', 'record'],
          onSelected: () => _openRoute(
            '/memory/voice-journal',
            (_) => const VoiceJournalScreen(),
            room: NeuraRoom.reflectionBay,
          ),
        ),
        PresenceCommand(
          id: 'dreams',
          title: 'Dreams',
          subtitle: 'Visualizer, calendar, monthly show, and themes.',
          icon: Icons.auto_awesome,
          keywords: const <String>['dream', 'sleep', 'calendar'],
          onSelected: () => _openRoute(
            '/spaces/dreams',
            (_) => const _DreamHub(),
            room: NeuraRoom.dreamAtrium,
          ),
        ),
        PresenceCommand(
          id: 'legacy',
          title: 'Legacy Vault',
          subtitle: 'Messages for future-you.',
          icon: Icons.auto_stories,
          keywords: const <String>['legacy', 'future', 'vault'],
          onSelected: () => _openRoute(
            '/memory/legacy',
            (_) => const LegacyHomeScreen(),
            room: NeuraRoom.legacyVault,
          ),
        ),
        PresenceCommand(
          id: 'memory-vault',
          title: 'Memory Vault',
          subtitle: 'Encrypted notes for what matters.',
          icon: Icons.lock_outline,
          keywords: const <String>['memory', 'encrypted', 'vault'],
          onSelected: () =>
              _openRoute('/memory/vault', (_) => const MemoryVaultScreen()),
        ),
        PresenceCommand(
          id: 'timeline',
          title: 'Life Timeline',
          subtitle: 'Your life, one event at a time.',
          icon: Icons.history_edu_outlined,
          keywords: const <String>['life', 'timeline', 'memory'],
          onSelected: () =>
              _openRoute('/memory/timeline', (_) => const LifeTimelineScreen()),
        ),
        PresenceCommand(
          id: 'support',
          title: 'Support Center',
          subtitle: 'Grounding tools and people to reach out to.',
          icon: Icons.health_and_safety_outlined,
          keywords: const <String>['support', 'grounding', 'safety'],
          onSelected: () =>
              _openRoute('/care/support', (_) => const SupportCenterScreen()),
        ),
        PresenceCommand(
          id: 'pay-it-forward',
          title: 'Pay It Forward',
          subtitle: 'Track kind acts and build a streak.',
          icon: Icons.volunteer_activism_outlined,
          keywords: const <String>['kindness', 'social', 'streak'],
          onSelected: () => _openRoute(
            '/spaces/pay-it-forward',
            (_) => const PayItForwardScreen(),
          ),
        ),
        PresenceCommand(
          id: 'quests',
          title: 'Quest Mode',
          subtitle: 'Tiny missions to build momentum.',
          icon: Icons.flag_outlined,
          keywords: const <String>['quest', 'goal', 'momentum'],
          onSelected: () =>
              _openRoute('/spaces/quests', (_) => const QuestModeScreen()),
        ),
        PresenceCommand(
          id: 'jokes',
          title: 'Neura Jokes',
          subtitle: 'Open an optional moment of humor.',
          icon: Icons.mood_outlined,
          keywords: const <String>['joke', 'humor', 'laugh'],
          onSelected: () =>
              _openRoute('/spaces/jokes', (_) => const JokeScreen()),
        ),
        PresenceCommand(
          id: 'therapy-journal',
          title: 'Therapy Journal',
          subtitle: 'Guided CBT, DBT, and ACT reflection prompts.',
          icon: Icons.self_improvement_outlined,
          keywords: const <String>['therapy', 'cbt', 'dbt', 'act'],
          onSelected: () => _openRoute(
              '/care/therapy-journal', (_) => const TherapyPathScreen()),
        ),
        PresenceCommand(
          id: 'money',
          title: 'Money Manager',
          subtitle: 'Track income and expenses on-device.',
          icon: Icons.account_balance_wallet_outlined,
          keywords: const <String>['money', 'budget', 'finance'],
          onSelected: () =>
              _openRoute('/spaces/money', (_) => const MoneyManagerScreen()),
        ),
        PresenceCommand(
          id: 'decision-path',
          title: 'Decision Path Helper',
          subtitle: 'Compare the fastest, safest, and cheapest paths.',
          icon: Icons.route_outlined,
          keywords: const <String>['decision', 'plan', 'compare'],
          onSelected: () => _openRoute(
            '/intelligence/decision-path',
            (_) => const DecisionPathScreen(),
          ),
        ),
        PresenceCommand(
          id: 'trusted-devices',
          title: 'Trusted Devices',
          subtitle: 'Review devices Neura is allowed to trust.',
          icon: Icons.verified_user_outlined,
          keywords: const <String>['device', 'trust', 'security'],
          onSelected: () => _openRoute(
            '/controls/trusted-devices',
            (_) => const TrustedDevicesScreen(),
          ),
        ),
        PresenceCommand(
          id: 'diagnostics',
          title: 'Diagnostics',
          subtitle: 'Health, logs, recovery, and support evidence.',
          icon: Icons.monitor_heart_outlined,
          keywords: const <String>['logs', 'recovery', 'health'],
          onSelected: _openDiagnostics,
        ),
        PresenceCommand(
          id: 'controls',
          title: 'Controls',
          subtitle: 'Privacy, safety, appearance, export, and wipe.',
          icon: Icons.tune_outlined,
          keywords: const <String>['settings', 'privacy', 'export', 'wipe'],
          onSelected: () => _onTab(4),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        SafeBoot.instance.safeMode,
        AmbientListeningPrefsController.instance.enabled,
        WakeWordPrefsController.instance.enabled,
        NeuraCompanionPresence.instance.state,
        ShellPrefsController.instance.prefs,
      ]),
      builder: (context, _) => StreamBuilder<dynamic>(
        // Safe Mode never subscribes to the optional cloud auth stream. The
        // local shell and its status remain fully usable without touching a
        // cloud-backed singleton.
        stream: SafeBoot.instance.safeMode.value
            ? null
            : (_authStateChanges ??= AuthService.onAuthStateChanged),
        builder: (context, _) => Scaffold(
          body: Stack(
            children: <Widget>[
              PresenceNavigationShell(
                currentIndex: _index,
                onDestinationSelected: _onTab,
                destinationPages: _destinationPages,
                commands: _commandCatalog,
                status: _presenceStatus(),
                now: const ProactiveBannerCard(),
                onOpenNeura: _openChat,
                onOpenDiagnostics: _openDiagnostics,
                room: (_shellState ?? NeuraShell.of(context)).room,
                preferences: ShellPrefsController.instance.prefs.value,
              ),
              const AmbientRecordingBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryHub extends StatelessWidget {
  const _MemoryHub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Your journal and encrypted memories stay local-first. Choose what '
            'to record, review, export, or preserve.',
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Get a prompt'),
              subtitle: const Text('Write privately with a time-aware prompt.'),
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.reflectionBay);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => JournalPromptScreen()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Voice journal'),
              subtitle: const Text(
                'Record only after opening the visible microphone screen.',
              ),
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.reflectionBay);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceJournalScreen()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Mood check‑in'),
              subtitle: const Text('Quick emotional snapshot.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MoodCheckInScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Memory Vault'),
              subtitle: const Text('Encrypted notes for what matters.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MemoryVaultScreen(),
                  settings: const RouteSettings(name: '/memory/vault'),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: const Text('Life Timeline'),
              subtitle: const Text('Your life, one event at a time.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LifeTimelineScreen(),
                  settings: const RouteSettings(name: '/memory/timeline'),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Text('Legacy Vault'),
              subtitle: const Text('Messages and memories for future-you.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegacyHomeScreen(),
                  settings: const RouteSettings(name: '/memory/legacy'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DreamHub extends StatelessWidget {
  const _DreamHub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dreams')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Dream hub: visualizer, calendar, and monthly "show" compilation.',
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Dream Visualizer'),
              subtitle: const Text('Timeline of dream scenes.'),
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.dreamAtrium);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DreamVisualizerScreen()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Dream Calendar'),
              subtitle: const Text('Browse dreams by date.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DreamJournalCalendarScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('Monthly Dream Show'),
              subtitle: const Text('Auto-compiled highlight reel.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MonthlyDreamShowScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Dream Themes'),
              subtitle: const Text('Recurring themes across your dream log.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DreamShow2Screen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
