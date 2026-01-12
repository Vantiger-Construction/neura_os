import 'dart:io';

import 'neura_android_bridge.dart';
import 'neura_windows_bridge.dart';

/// Simple facade so your UI doesn't care about platform specifics.
class NeuraBridge {
  final NeuraAndroidBridge? _android;
  final NeuraWindowsBridge? _windows;

  NeuraBridge._(this._android, this._windows);

  static NeuraBridge forPlatform({String? unityExePath}) {
    if (Platform.isAndroid) return NeuraBridge._(NeuraAndroidBridge(), null);
    if (Platform.isWindows) {
      if (unityExePath == null || unityExePath.isEmpty) {
        throw ArgumentError("unityExePath is required on Windows.");
      }
      return NeuraBridge._(null, NeuraWindowsBridge(unityExePath: unityExePath));
    }
    throw UnsupportedError("NeuraBridge supports Android + Windows in this pack.");
  }

  Future<void> start() async {
    if (_windows != null) await _windows.start();
  }

  void onEvent(void Function(Map<String, dynamic>) cb) {
    _windows?.onEvent(cb);
    // Android -> Flutter events added in next patch (needs Java->MethodChannel back).
  }

  Future<void> sendSetState({
    required String mood,
    required double energy,
    required String room,
  }) async {
    final msg = {
      "type": "SET_STATE",
      "mood": mood,
      "energy": energy,
      "room": room,
    };
    await _send(msg);
  }

  Future<void> sendAction(String action, String value) async {
    final msg = {"type": "ACTION", "action": action, "value": value};
    await _send(msg);
  }

  Future<void> _send(Map<String, dynamic> msg) async {
    if (_android != null) {
      await _android.send(msg);
    } else {
      _windows?.send(msg);
    }
  }
}
