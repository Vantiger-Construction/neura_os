import 'package:flutter/foundation.dart';

/// Where a visible reply was produced.
enum NeuraReplyRoute { onDevice, approvedCloud }

/// A metadata-only explanation of the context used for one reply.
///
/// This deliberately excludes filenames, memory contents, prompts, message
/// text, provider credentials, and private values. It is safe to keep beside
/// the visible in-memory chat line and is not persisted automatically.
@immutable
class NeuraContextReceipt {
  const NeuraContextReceipt({
    required this.route,
    required this.roomId,
    required this.usedVisibleHistory,
    required this.usedSelectedText,
    required this.usedPermittedMemory,
    required this.historyIncludedPrivateContext,
    required this.usedImage,
    required this.savedToLongTermMemory,
  });

  final NeuraReplyRoute route;
  final String roomId;
  final bool usedVisibleHistory;
  final bool usedSelectedText;
  final bool usedPermittedMemory;
  final bool historyIncludedPrivateContext;
  final bool usedImage;
  final bool savedToLongTermMemory;

  String get routeLabel => switch (route) {
        NeuraReplyRoute.onDevice => 'On-device reply',
        NeuraReplyRoute.approvedCloud => 'Approved cloud reply',
      };

  List<String> get contextLabels => <String>[
        if (usedVisibleHistory) 'Visible chat history',
        if (!usedVisibleHistory) 'Current message only',
        if (usedSelectedText) 'Selected text',
        if (usedPermittedMemory) 'Permitted memories',
        if (usedImage && route == NeuraReplyRoute.onDevice)
          'Image attached (pixels not inspected on-device)',
        if (usedImage && route == NeuraReplyRoute.approvedCloud)
          'Attached image',
        if (historyIncludedPrivateContext) 'Earlier private-context reply',
      ];

  String get memoryLabel => savedToLongTermMemory
      ? 'This reply may be remembered under the room policy.'
      : 'This reply was not added to long-term memory.';

  Map<String, Object> toMetadata() => <String, Object>{
        'route': route.name,
        'room_id': roomId,
        'visible_history': usedVisibleHistory,
        'selected_text': usedSelectedText,
        'permitted_memory': usedPermittedMemory,
        'private_history': historyIncludedPrivateContext,
        'image': usedImage,
        'saved_to_long_term_memory': savedToLongTermMemory,
      };
}
