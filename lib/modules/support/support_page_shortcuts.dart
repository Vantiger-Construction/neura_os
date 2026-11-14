import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _LeaveSupportIntent extends Intent {
  const _LeaveSupportIntent();
}

/// Escape leaves the current support route; its normal disposal clears drafts.
class SupportPageShortcuts extends StatelessWidget {
  const SupportPageShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _LeaveSupportIntent()
        },
        child: Actions(
          actions: {
            _LeaveSupportIntent:
                CallbackAction<_LeaveSupportIntent>(onInvoke: (_) {
              final navigator = Navigator.maybeOf(context);
              if (navigator?.canPop() ?? false) {
                navigator!.maybePop();
              } else {
                FocusScope.of(context).unfocus();
              }
              return null;
            }),
          },
          child: Focus(autofocus: true, child: child),
        ),
      );
}
