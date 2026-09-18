import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/sync_recovery.dart';

void main() {
  test(
      'acknowledgement cannot overwrite concurrent edits or resurrect deletion',
      () {
    expect(
        mayApplySyncAcknowledgement(
            currentRevision: 'old', sentRevision: 'old'),
        true);
    expect(
        mayApplySyncAcknowledgement(
            currentRevision: 'new', sentRevision: 'old'),
        false);
    expect(
        mayApplySyncAcknowledgement(currentRevision: null, sentRevision: 'old'),
        false);
  });
  test('duplicate sync joins current attempt and recovery can retry afterward',
      () async {
    final gate = Completer<SyncResult>();
    final flight = SyncSingleFlight();
    var calls = 0;
    final a = flight.run(() {
      calls++;
      return gate.future;
    });
    final b = flight.run(() {
      calls++;
      return gate.future;
    });
    expect(identical(a, b), true);
    gate.complete(const SyncResult(SyncOutcome.failed));
    expect((await a).succeeded, false);
    await flight.run(() async {
      calls++;
      return const SyncResult(SyncOutcome.complete);
    });
    expect(calls, 2);
  });
}
