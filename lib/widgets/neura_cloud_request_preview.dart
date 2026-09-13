import 'package:flutter/material.dart';

import '../services/neura_model_router.dart';

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing is sent unless you approve this request.',
          ),
          const SizedBox(height: 12),
          Text('Purpose: ${preview.purpose}'),
          Text('Messages: ${preview.messageCount}'),
          Text('Approximate characters: ${preview.characterCount}'),
          Text('Includes an image: ${preview.includesImage ? "Yes" : "No"}'),
          Text(
            'Includes private context: '
            '${preview.includesPrivateContext ? "Yes" : "No"}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Approval applies once. A fallback provider requires another '
            'preview and approval.',
          ),
        ],
      ),
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
