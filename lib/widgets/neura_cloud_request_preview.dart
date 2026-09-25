import 'package:flutter/material.dart';

import '../services/neura_model_router.dart';
import '../services/neura_model_types.dart';

Future<bool> showNeuraCloudRequestPreview(
  BuildContext context,
  NeuraCloudRequestPreview preview,
) async {
  if (!context.mounted) return false;
  final decision = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text('Send to ${preview.provider.label}?'),
      content: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing is sent unless you approve this request.',
          ),
          const SizedBox(height: 12),
          Text('Approval state: ${preview.approvalState.name}'),
          Text('Destination: ${preview.audience.host}'),
          Text(
            preview.retryCount == 0
                ? 'Attempt: initial request'
                : 'Attempt: exact retry ${preview.retryCount}',
          ),
          Text(
            'Request fingerprint: '
            '${preview.promptDigest.substring(0, 12)}…',
          ),
          Text(
            'Shared caching: '
            '${preview.privateCacheProhibited ? "Prohibited" : "Allowed"}',
          ),
          const SizedBox(height: 12),
          Text('Purpose: ${preview.purpose}'),
          Text('Messages: ${preview.messageCount}'),
          if (preview.omittedMessageCount > 0)
            Text(
              'Older messages omitted for reliability: '
              '${preview.omittedMessageCount}',
            ),
          Text('Approximate characters: ${preview.characterCount}'),
          Text('Includes an image: ${preview.includesImage ? "Yes" : "No"}'),
          Text(
            'Includes private context: '
            '${preview.includesPrivateContext ? "Yes" : "No"}',
          ),
          if (preview.textPreview.isNotEmpty)
            ExpansionTile(
              title: const Text('Review text and context'),
              children: [SelectableText(preview.textPreview)],
            ),
          const SizedBox(height: 12),
          const Text(
            'Approval applies once. An exact retry or fallback provider '
            'requires another preview and approval.',
          ),
        ],
      )),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep local'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Approve once'),
        ),
      ],
    ),
  );
  return decision == true;
}
