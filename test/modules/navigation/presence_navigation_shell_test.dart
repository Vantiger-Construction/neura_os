import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_companion/modules/navigation/presence_navigation_shell.dart';

void main() {
  group('PresenceNavigationLayoutPolicy', () {
    test('uses a bottom rail below the wide breakpoint', () {
      expect(
        PresenceNavigationLayoutPolicy.modeForWidth(959),
        PresenceLayoutMode.compact,
      );
    });

    test('uses a side rail at and above the wide breakpoint', () {
      expect(
        PresenceNavigationLayoutPolicy.modeForWidth(960),
        PresenceLayoutMode.wide,
      );
      expect(
        PresenceNavigationLayoutPolicy.modeForWidth(1440),
        PresenceLayoutMode.wide,
      );
    });
  });

  group('presenceCommandMatches', () {
    final command = PresenceCommand(
      id: 'memory-vault',
      title: 'Memory Vault',
      subtitle: 'Encrypted notes for what matters.',
      icon: Icons.lock_outline,
      keywords: const <String>['private', 'journal'],
      onSelected: () {},
    );

    test('matches title, subtitle, and keywords without case sensitivity', () {
      expect(presenceCommandMatches(command, 'MEMORY'), isTrue);
      expect(presenceCommandMatches(command, 'encrypted'), isTrue);
      expect(presenceCommandMatches(command, 'JOURNAL'), isTrue);
    });

    test('matches an empty query and rejects unrelated text', () {
      expect(presenceCommandMatches(command, '  '), isTrue);
      expect(presenceCommandMatches(command, 'weather'), isFalse);
    });
  });

  group('PresenceNavigationShell', () {
    final commands = <PresenceCommand>[
      PresenceCommand(
        id: 'memory-vault',
        title: 'Memory Vault',
        subtitle: 'Encrypted notes for what matters.',
        icon: Icons.lock_outline,
        keywords: const <String>['private', 'journal'],
        onSelected: () {},
      ),
    ];
    const status = PresenceShellStatus(
      safeMode: true,
      cloudLabel: 'Cloud blocked',
      voiceLabel: 'Voice off',
      presenceLabel: 'Safe Mode · audio is off',
    );

    Future<void> pumpShell(WidgetTester tester, Size size) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: PresenceNavigationShell(
            currentIndex: 0,
            onDestinationSelected: (_) {},
            destinationPages: const <Widget>[
              SizedBox.shrink(),
              Center(child: Text('Spaces surface')),
              Center(child: Text('Care surface')),
              Center(child: Text('Memory surface')),
              Center(child: Text('Controls surface')),
            ],
            commands: commands,
            status: status,
            now: const Text('A quiet local moment'),
            onOpenNeura: () {},
            onOpenDiagnostics: () {},
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('uses a dedicated stage and side rail on wide screens',
        (tester) async {
      await pumpShell(tester, const Size(1280, 800));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Neura is here'), findsOneWidget);
      expect(find.text('Approval every time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses a compact stage and bottom rail on phone screens',
        (tester) async {
      await pumpShell(tester, const Size(400, 860));

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Neura is here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens a searchable secondary-command palette', (tester) async {
      await pumpShell(tester, const Size(400, 860));

      await tester.tap(find.text('Ask Neura or type a command…'));
      await tester.pumpAndSettle();
      expect(find.text('Memory Vault'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'unrelated');
      await tester.pump();
      expect(find.text('No matching Neura spaces.'), findsOneWidget);
    });
  });
}
