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

  test('on-device image receipt does not claim pixel inspection', () {
    const receipt = NeuraContextReceipt(
      route: NeuraReplyRoute.onDevice,
      roomId: 'focus_hub',
      usedVisibleHistory: false,
      usedSelectedText: false,
      usedPermittedMemory: false,
      historyIncludedPrivateContext: false,
      usedImage: true,
      savedToLongTermMemory: false,
    );

    expect(
      receipt.contextLabels,
      contains('Image attached (pixels not inspected on-device)'),
    );
    expect(receipt.contextLabels, isNot(contains('Attached image')));

    final metadata = receipt.toMetadata();
    expect(metadata['image'], isTrue);
    expect(metadata.keys, isNot(contains('filename')));
    expect(metadata.keys, isNot(contains('prompt')));
    expect(metadata.keys, isNot(contains('text')));
  });
}
