import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/screens/help_screen.dart';

void main() {
  testWidgets('guides users to current local activities and save controls',
      (tester) async {
    await _openHelp(tester);
    final guidance = await _readHelp(tester);

    for (final instruction in [
      'Ask Neura or type a command…',
      'Find a room or action',
      'Controls opens Settings',
      'do not require an account',
      'Journal Prompt',
      'Write a response',
      'Save response',
      'Saved to your local journal',
      'Saved responses',
      'Text journaling works offline on this device',
      'Mood Check-In',
      'your own rating from 0 to 10',
      'Save check-in',
      'Mood History',
      'Support Center',
      'Help me through this',
      'Quiet writing, Grounding pause or One small plan',
      'fixed, optional reflection activities',
      'Writing here is temporary',
      'Use Journal Prompt for words you want to save',
      'Open Spaces and choose a room card',
      'Choose a room',
    ]) {
      expect(guidance, contains(instruction), reason: instruction);
    }
  });

  testWidgets('explains optional speech, model and data prerequisites',
      (tester) async {
    await _openHelp(tester);
    final guidance = await _readHelp(tester);

    for (final prerequisite in [
      'microphone access and a working device speech service',
      'Windows uses Windows speech recognition',
      'phones use their platform speech service',
      'Voice services may need an internet connection',
      'Start listening',
      'Stop listening',
      'Save transcript',
      'Safe Mode keeps the microphone off',
      'provider key in Controls > AI Provider',
      'your approval for each request',
      'Read the request preview before approving',
      'Offline Ollama requires a Windows build',
      'Ollama running on this PC',
      'qwen3:4b-instruct',
      '7 GiB total RAM and 3.5 GiB available',
      'The model can make mistakes',
      'Controls > Privacy & Safety > Data Controls',
      "Decrypted Legacy Vault exports require the capsules' passphrase",
      'Read the confirmation before deleting',
      'read the result and restart Neura before continuing',
      'Copies already shared outside Neura are unaffected',
      'Device lock requires supported device authentication',
      'cross-device sync is still being verified',
    ]) {
      expect(guidance, contains(prerequisite), reason: prerequisite);
    }
  });

  testWidgets('does not promise unsupported release capabilities',
      (tester) async {
    await _openHelp(tester);
    final guidance = (await _readHelp(tester)).toLowerCase();

    for (final claim in [
      'log in or create an account to get started',
      'daily rituals in analytics',
      'community challenges',
      'share posts',
      'public feed',
      'interpret your dreams',
      'ai dream interpretation',
      'ai mood analysis',
      'customize your ai companion avatar',
      'seamlessly',
      'automatic synchronization',
      'manage subscriptions',
      'clinically proven',
      'diagnoses',
      'treats health conditions',
      'all data is encrypted',
    ]) {
      expect(guidance, isNot(contains(claim)), reason: claim);
    }
    expect(guidance, contains('seek a qualified professional'));
  });

  for (final brightness in Brightness.values) {
    testWidgets('Help stays readable and Back works in ${brightness.name} mode',
        (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await _openHelp(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        brightness: brightness,
      );

      expect(find.text('Getting Started'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Welcome to Neura Companion!')),
        matchesSemantics(
          label: 'Welcome to Neura Companion!',
          isHeader: true,
        ),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      final guidance = await _readHelp(tester);
      expect(guidance, contains('Privacy and local data'));
      expect(guidance, contains('Explore at your own pace with Neura'));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsNothing);
      expect(find.text('Open Help'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openHelp(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
          ),
          child: const Text('Open Help'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open Help'));
  await tester.pumpAndSettle();
}

Future<String> _readHelp(WidgetTester tester) async {
  final seen = <String>{};
  final screen = find.byType(HelpScreen);
  final scrollable = find.descendant(
    of: screen,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  final texts = find.descendant(of: screen, matching: find.byType(Text));

  for (var step = 0; step < 80; step++) {
    for (final text in tester.widgetList<Text>(texts)) {
      final words = text.data ?? text.textSpan?.toPlainText();
      if (words != null) seen.add(words);
    }
    expect(tester.takeException(), isNull);
    if (position.pixels >= position.maxScrollExtent) return seen.join('\n');
    await tester.drag(scrollable, const Offset(0, -360));
    await tester.pumpAndSettle();
  }
  throw TestFailure('Could not reach the end of the Help guidance.');
}
