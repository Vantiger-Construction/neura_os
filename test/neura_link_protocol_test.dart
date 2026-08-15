import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_link/envelope.dart';

void main() {
  test('envelope round-trips the frozen v1 contract', () {
    const envelope = Envelope(
      kind: 'speak_delta',
      id: 'utterance-1',
      data: {'utterance_id': 'utterance-1', 'delta': 'Hello'},
    );

    final decoded = Envelope.fromJson(envelope.toJson());
    expect(decoded.version, 1);
    expect(decoded.kind, 'speak_delta');
    expect(decoded.id, 'utterance-1');
    expect(decoded.data['delta'], 'Hello');
  });

  test('unknown optional fields do not break decoding', () {
    final decoded = Envelope.fromJson({
      'v': 1,
      'kind': 'diagnostics',
      'id': 'diag-1',
      'data': <String, dynamic>{},
      'future_field': true,
    });
    expect(decoded.kind, 'diagnostics');
  });
}
