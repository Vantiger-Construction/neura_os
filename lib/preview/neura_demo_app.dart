import 'package:flutter/material.dart';

import '../modules/human/accessibility_screen.dart';
import '../modules/human/human_media_query.dart';
import '../modules/human/human_prefs.dart';
import '../modules/mood/mood_checkin_screen.dart';
import '../modules/mood/mood_history_screen.dart';
import '../modules/support/appointment_prep_screen.dart';
import '../modules/support/guided_support_activity.dart';
import '../modules/support/guided_support_screen.dart';
import '../modules/support/human_support_screen.dart';
import '../modules/support/support_suggestion_screen.dart';
import '../modules/support/usability_feedback_screen.dart';
import '../modules/support/wellbeing_home_card.dart';
import '../modules/support/wellbeing_session_screen.dart';
import '../theme/app_theme.dart';
import 'neura_demo_session.dart';

class NeuraDemoApp extends StatefulWidget {
  const NeuraDemoApp({super.key, this.session});
  final NeuraDemoSession? session;
  @override
  State<NeuraDemoApp> createState() => _NeuraDemoAppState();
}

class _NeuraDemoAppState extends State<NeuraDemoApp>
    with WidgetsBindingObserver {
  late final NeuraDemoSession _session = widget.session ?? NeuraDemoSession();
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _session.clearCopy();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  Widget _unavailable(BuildContext context) => const Scaffold(
        appBar: _PreviewAppBar(),
        body: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'Personal journals and trusted-contact records are unavailable in this preview. '
                'Try quiet writing or the sample check-ins instead. No private record has been opened.')),
      );

  Widget _destination(WellbeingDestination destination) =>
      switch (destination) {
        WellbeingDestination.settle => GuidedSupportScreen(
            store: _session.support,
            copyText: _session.copyText,
            trustedContactsBuilder: _unavailable),
        WellbeingDestination.quietWriting => GuidedSupportScreen(
            store: _session.support,
            initialActivity: GuidedSupportActivity.quietWriting,
            copyText: _session.copyText,
            trustedContactsBuilder: _unavailable),
        WellbeingDestination.smallStep => const WellbeingSessionScreen(),
        WellbeingDestination.reminder =>
          const WellbeingSessionScreen(reminder: true),
        WellbeingDestination.reachSomeone => HumanSupportScreen(
            copyText: _session.copyText, trustedContactsBuilder: _unavailable),
        WellbeingDestination.urgentHelp => HumanSupportScreen(
            urgentOnly: true,
            copyText: _session.copyText,
            trustedContactsBuilder: _unavailable),
        WellbeingDestination.journal => Builder(builder: _unavailable),
        WellbeingDestination.checkIn =>
          MoodCheckInScreen(save: _session.addEntry),
        WellbeingDestination.history =>
          MoodHistoryScreen(load: _session.loadEntries),
        WellbeingDestination.suggestions =>
          SupportSuggestionScreen(store: _session.support),
        WellbeingDestination.appointment => AppointmentPrepScreen(
            load: _session.loadEntries, copyText: _session.copyText),
        WellbeingDestination.accessibility => AccessibilityScreen.preview(
            preferences: _session.preferences,
            updatePreferences: _session.updatePreferences),
        WellbeingDestination.feedback =>
          UsabilityFeedbackScreen(copyText: _session.copyText),
      };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HumanPrefs>(
        valueListenable: _session.preferences,
        builder: (context, prefs, _) => MaterialApp(
          navigatorKey: _navigator,
          debugShowCheckedModeBanner: false,
          title: 'Neura — Sample data preview',
          theme: AppTheme.light(
              highContrast: prefs.highContrast ||
                  (MediaQuery.maybeOf(context)?.highContrast ?? false)),
          darkTheme: AppTheme.dark(
              highContrast: prefs.highContrast ||
                  (MediaQuery.maybeOf(context)?.highContrast ?? false)),
          themeMode: switch (prefs.theme) {
            NeuraThemePref.dark => ThemeMode.dark,
            NeuraThemePref.light => ThemeMode.light,
            NeuraThemePref.system => ThemeMode.system
          },
          highContrastTheme: AppTheme.light(highContrast: true),
          highContrastDarkTheme: AppTheme.dark(highContrast: true),
          builder: (context, child) => MediaQuery(
            data: applyHumanAccessibilityPreferences(
                MediaQuery.of(context), prefs),
            child: Column(children: [
              Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: SafeArea(
                      bottom: false,
                      child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Semantics(
                              container: true,
                              child: const Text(
                                  'SAMPLE DATA PREVIEW · No personal Neura files, voice, models or cloud. '
                                  'Copy buttons use a temporary demo clipboard.'))))),
              Expanded(child: child ?? const SizedBox.shrink()),
            ]),
          ),
          home: Scaffold(
              appBar: AppBar(title: const Text('Try Neura safely')),
              body: SafeArea(
                  child: Center(
                      child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  const Text(
                      'These are the actual wellbeing screens with sample check-ins and in-memory preferences. '
                      'Use fictional text. Your changes disappear when the preview closes or hot restarts.'),
                  const SizedBox(height: 12),
                  WellbeingHomeCard(destinationBuilder: _destination),
                  const SizedBox(height: 12),
                  const Text(
                      'Unavailable here: real journals and contacts, profiles, backup/restore/wipe, '
                      'microphones, speakers, model engines, cloud providers and the floating companion. '
                      'This preview does not validate those features.'),
                  ValueListenableBuilder<String?>(
                      valueListenable: _session.clipboard,
                      builder: (_, copied, __) => copied == null
                          ? const SizedBox.shrink()
                          : Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                            'Demo clipboard (inside this session only)'),
                                        Text(copied),
                                        TextButton(
                                            onPressed: _session.clearCopy,
                                            child: const Text(
                                                'Clear demo clipboard')),
                                      ])))),
                ]),
              )))),
        ),
      );
}

class _PreviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PreviewAppBar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('Unavailable in preview'));
}
