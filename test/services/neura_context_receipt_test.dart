import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_context_receipt.dart';

void main() {
  test('receipt reports categories without retaining private content', () {
    const receipt = NeuraContextReceipt(
      route: NeuraReplyRoute.approvedCloud,
      roomId: 'reflection_bay',
      usedVisibleHistory: true,
      usedSelectedText: true,
      usedPermittedMemory: true,
      historyIncludedPrivateContext: false,
      usedImage: false,
      savedToLongTermMemory: false,
    );

    final metadata = receipt.toMetadata();
    expect(metadata['route'], 'approvedCloud');
    expect(metadata['selected_text'], isTrue);
    expect(metadata['permitted_memory'], isTrue);
    expect(metadata.keys, isNot(contains('filename')));
    expect(metadata.keys, isNot(contains('prompt')));
    expect(metadata.keys, isNot(contains('text')));
    expect(receipt.memoryLabel, contains('not added'));
  });
}
