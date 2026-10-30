import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/modules/memory/memory_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

import '../helpers/companion_memory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'memory route denies automatic recall, reviews explicitly and clears on revocation',
      (tester) async {
    late CompanionMemoryFixture f;
    await tester.runAsync(() async {
      f = await CompanionMemoryFixture.create();
      await f.disk.run(() => f.seed());
    });
    await tester
        .pumpWidget(MaterialApp(home: MemoryScreen(memoryService: f.memory)));
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => !field.enableIMEPersonalizedLearning),
        true);
    expect(f.crypto.decryptions, 0);
    expect(find.text('Synthetic companion note'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Review saved notes on this device'));
      await f.crypto.decrypted.future;
    });
    await tester.pumpAndSettle();
    expect(find.text('Synthetic companion note'), findsOneWidget);
    f.memory.revokePermissions();
    await tester.pump();
    expect(find.text('Synthetic companion note'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Safe Mode clears reviewed values and never restores them on return',
      (tester) async {
    late CompanionMemoryFixture f;
    await tester.runAsync(() async {
      f = await CompanionMemoryFixture.create();
      await f.disk.run(() => f.seed());
    });
    await tester
        .pumpWidget(MaterialApp(home: MemoryScreen(memoryService: f.memory)));
    await tester.runAsync(() async {
      await tester.tap(find.text('Review saved notes on this device'));
      await f.crypto.decrypted.future;
    });
    await tester.pumpAndSettle();
    expect(find.text('Synthetic companion note'), findsOneWidget);
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    expect(find.text('Synthetic companion note'), findsNothing);
    SafeBoot.instance.safeMode.value = false;
    await tester.pump();
    expect(find.text('Synthetic companion note'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('idle permission timer revokes at the five-minute boundary',
      (tester) async {
    late CompanionMemoryFixture f;
    await tester.runAsync(() async {
      f = await CompanionMemoryFixture.create();
    });
    final permission = f.grant(CompanionMemoryUse.review);
    f.now = f.now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(permission.lease.isRevoked, true);
  });

  testWidgets('closing memory route revokes an unfinished restore',
      (tester) async {
    late CompanionMemoryFixture f;
    await tester.runAsync(() async {
      f = await CompanionMemoryFixture.create();
      await f.disk.run(() => f.seed());
    });
    f.crypto.pauseRead = true;
    await tester
        .pumpWidget(MaterialApp(home: MemoryScreen(memoryService: f.memory)));
    await tester.runAsync(() async {
      await tester.tap(find.text('Review saved notes on this device'));
      await f.crypto.entered.future;
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      f.crypto.release();
      await f.crypto.decrypted.future;
    });
    await tester.pumpAndSettle();
    expect(find.text('Synthetic companion note'), findsNothing);
    expect(tester.takeException(), isNull);
    // Closing the route does not wipe the durable note.
    await tester.runAsync(() async {
      final permission = f.grant(CompanionMemoryUse.review);
      expect(
          (await f.memory.recall(permission, use: CompanionMemoryUse.review))
              .single
              .value,
          'Synthetic companion note');
    });
  });
}
