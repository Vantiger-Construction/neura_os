import 'package:flutter/material.dart';

import 'neura_shell_root.dart';
import 'neura_shell_state.dart';

/// Convenience accessor for Neura's global "room" state.
class NeuraShell {
  static NeuraShellState of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<NeuraShellInherited>();
    assert(inherited != null,
        'NeuraShellRoot not found above in the widget tree.');
    return inherited!.notifier;
  }
}
