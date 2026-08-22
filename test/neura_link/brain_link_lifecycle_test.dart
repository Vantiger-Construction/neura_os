import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_link/brain_link.dart';

void main() {
  test(
    'brain link fails closed before connection and cannot restart after dispose',
    () async {
      final link = BrainLink(url: 'ws://127.0.0.1:1');
      final states = <BrainConnectionState>[];
      final subscription = link.states.listen(states.add);

      expect(link.send('diagnostics_request', const {}), isFalse);

      await link.dispose();

      expect(states, contains(BrainConnectionState.stopped));
      expect(link.start, throwsStateError);

      await subscription.cancel();
    },
  );
}
