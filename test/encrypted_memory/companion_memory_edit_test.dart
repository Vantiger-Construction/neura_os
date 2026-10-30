import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/encrypted_memory/encrypted_memory_contracts.dart';
import '../helpers/companion_memory_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CompanionMemoryFixture f;
  setUp(() async => f = await CompanionMemoryFixture.create());
  test(
      'correct and forget require separate gestures and revoke earlier recall',
      () => f.disk.run(() async {
            await f.seed('One step at a time');
            final view = f.grant(CompanionMemoryUse.review);
            final note =
                (await f.memory.recall(view, use: CompanionMemoryUse.review))
                    .single;
            await expectLater(
                f.memory.changeNote(view,
                    recordId: note.id, replacement: 'Short replies'),
                throwsA(isA<EncryptedMemoryPolicyViolation>()));
            final prompt = f.grant(CompanionMemoryUse.prompt);
            final correction = f.grant(CompanionMemoryUse.correct);
            expect(
                await f.memory.changeNote(correction,
                    recordId: note.id, replacement: 'Short replies'),
                true);
            expect(prompt.requireCurrent,
                throwsA(isA<EncryptedMemoryPolicyViolation>()));
            expect(view.requireCurrent,
                throwsA(isA<EncryptedMemoryPolicyViolation>()));
            correction.revoke();
            final revised = (await f.memory.recall(
                    f.grant(CompanionMemoryUse.review),
                    use: CompanionMemoryUse.review))
                .single;
            expect(revised.value, 'Short replies');
            expect(revised.id, note.id);
            expect(revised.provenance.reason, 'user_corrected_companion_note');
            final forgotten = f.grant(CompanionMemoryUse.forget);
            expect(
                await f.memory.changeNote(forgotten, recordId: note.id), true);
            forgotten.revoke();
            final owner = f.owner();
            final fresh = owner.authorize(CompanionMemoryUse.review,
                directUserGesture: true);
            expect(await owner.recall(fresh, use: CompanionMemoryUse.review),
                isEmpty);
            fresh.revoke();
          }));
  test(
      'revoked correction cannot restore old or replacement text after an async write',
      () => f.disk.run(() async {
            await f.seed('Original note');
            final note = (await f.memory.recall(
                    f.grant(CompanionMemoryUse.review),
                    use: CompanionMemoryUse.review))
                .single;
            f.crypto.pauseWrite = true;
            final permission = f.grant(CompanionMemoryUse.correct);
            final changing = expectLater(
                f.memory.changeNote(permission,
                    recordId: note.id, replacement: 'Replacement'),
                throwsA(isA<EncryptedMemoryPolicyViolation>()));
            await f.crypto.entered.future;
            permission.revoke();
            f.crypto.release();
            await changing;
            final records = await f.memory.recall(
                f.grant(CompanionMemoryUse.review),
                use: CompanionMemoryUse.review);
            expect(records.single.value, 'Original note');
          }));
}
