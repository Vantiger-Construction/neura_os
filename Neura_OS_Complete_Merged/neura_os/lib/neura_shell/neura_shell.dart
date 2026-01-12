import 'package:flutter/material.dart';

import 'neura_shell_state.dart';

/// Convenience accessor for Neura's global "room" state.
class NeuraShell {
  static NeuraShellState of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<InheritedNotifier<NeuraShellState>>();
    final notifier = inherited?.notifier;
    assert(notifier != null, 'NeuraShellRoot not found above in the widget tree.');
    return notifier!;
  }
}
