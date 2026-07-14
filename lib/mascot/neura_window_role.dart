import 'package:flutter/services.dart';

/// Tells this engine whether it's the main app window or the floating
/// mascot window, and its real window_manager_plus window id.
///
/// Dart entrypoint arguments (`args` in `main()`) do not reliably reach a
/// secondary window_manager_plus engine created in the same process on this
/// Flutter build -- confirmed empty via diagnostic logging even though the
/// native side constructs them correctly -- so identity is instead read
/// from a dedicated native channel, populated directly from the C++
/// window-creation callback in windows/runner/main.cpp.
class NeuraWindowRole {
  static const MethodChannel _channel = MethodChannel('neura/window_role');

  static Future<({int windowId, bool isMascot})> get() async {
    final result = await _channel.invokeMapMethod<String, Object?>('getRole');
    return (
      windowId: result?['windowId'] as int? ?? 0,
      isMascot: result?['isMascot'] as bool? ?? false,
    );
  }
}
