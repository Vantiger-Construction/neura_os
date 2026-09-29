import 'package:flutter/material.dart';

import '../services/neura_context_receipt.dart';

class NeuraContextReceiptChip extends StatelessWidget {
  const NeuraContextReceiptChip({super.key, required this.receipt});

  final NeuraContextReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        receipt.route == NeuraReplyRoute.onDevice
            ? Icons.phone_android_outlined
            : Icons.cloud_done_outlined,
        size: 15,
      ),
      label: const Text('Context used'),
      tooltip: 'See what Neura used for this reply',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Reply context receipt',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text('${receipt.routeLabel} · ${receipt.roomId}'),
                const SizedBox(height: 12),
                for (final label in receipt.contextLabels)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline, size: 20),
                    title: Text(label),
                  ),
                const Divider(),
                Text(receipt.memoryLabel),
                const SizedBox(height: 8),
                Text(
                  'Only these labels are retained with the visible chat. '
                  'The receipt contains no prompt, filename, memory text, '
                  'journal text, or credential.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
