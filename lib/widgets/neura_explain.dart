import 'package:flutter/material.dart';

/// Lightweight "Why am I seeing this?" helper.
///
/// No extra dependencies. Works anywhere.
class NeuraExplainSpec {
  final String title;
  final String body;
  final List<String> bullets;
  final String? footer;

  const NeuraExplainSpec({
    required this.title,
    required this.body,
    this.bullets = const [],
    this.footer,
  });
}

Future<void> showNeuraExplain(
  BuildContext context, {
  required NeuraExplainSpec spec,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      spec.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(spec.body, style: theme.textTheme.bodyMedium),
              if (spec.bullets.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...spec.bullets.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.circle, size: 8),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b)),
                      ],
                    ),
                  ),
                ),
              ],
              if ((spec.footer ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  spec.footer!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Tiny "Why?" chip usable inline in list tiles, headers, etc.
class WhyChip extends StatelessWidget {
  final NeuraExplainSpec spec;

  const WhyChip({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.help_outline, size: 18),
      label: const Text('Why?'),
      onPressed: () => showNeuraExplain(context, spec: spec),
    );
  }
}

/// Convenience class for showing explanations.
class NeuraExplain {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
    List<String> bullets = const [],
    String? footer,
  }) async {
    await showNeuraExplain(
      context,
      spec: NeuraExplainSpec(
        title: title,
        body: body,
        bullets: bullets,
        footer: footer,
      ),
    );
  }
}
