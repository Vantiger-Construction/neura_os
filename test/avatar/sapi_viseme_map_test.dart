import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/viseme/sapi_viseme_map.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';

void main() {
  test('covers every SPVISEMES id with a bounded mouth amount', () {
    for (var id = 0; id <= NeuraSapiVisemes.maxId; id++) {
      expect(NeuraSapiVisemes.isValid(id), isTrue);
      final open = NeuraSapiVisemes.mouthOpen(id);
      expect(open, inInclusiveRange(0.0, 1.0), reason: 'id $id');
    }
  });

  test('silence and bilabials close the mouth', () {
    expect(NeuraSapiVisemes.viseme(0), NeuraViseme.rest);
    expect(NeuraSapiVisemes.mouthOpen(0), 0.0);
    expect(NeuraSapiVisemes.viseme(21), NeuraViseme.MBP);
    expect(NeuraSapiVisemes.mouthOpen(21), 0.0);
  });

  test('distinct phoneme classes map to distinct shapes', () {
    expect(NeuraSapiVisemes.viseme(2), NeuraViseme.AI); // aa
    expect(NeuraSapiVisemes.viseme(6), NeuraViseme.I); // iy
    expect(NeuraSapiVisemes.viseme(8), NeuraViseme.O); // ow
    expect(NeuraSapiVisemes.viseme(15), NeuraViseme.SZN); // s z
    expect(NeuraSapiVisemes.viseme(16), NeuraViseme.CHJSH); // sh
    expect(NeuraSapiVisemes.viseme(17), NeuraViseme.TH); // th
    expect(NeuraSapiVisemes.viseme(18), NeuraViseme.FV); // f v
    expect(NeuraSapiVisemes.viseme(20), NeuraViseme.KG); // k g
    // Open vowels open wider than sibilants.
    expect(NeuraSapiVisemes.mouthOpen(2),
        greaterThan(NeuraSapiVisemes.mouthOpen(15)));
  });

  test('out-of-range ids rest closed instead of throwing', () {
    for (final id in [-1, 22, 255, 1 << 20]) {
      expect(NeuraSapiVisemes.isValid(id), isFalse);
      expect(NeuraSapiVisemes.viseme(id), NeuraViseme.rest);
      expect(NeuraSapiVisemes.mouthOpen(id), 0.0);
    }
  });
}
