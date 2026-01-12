import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Android-only Unity -> Flutter event stream.
/// Unity emits JSON line strings; we parse to Map.
class NeuraAndroidEventBridge {
  static const MethodChannel _ch = MethodChannel('neura/unity_events');

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  NeuraAndroidEventBridge() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onUnityEvent') {
        final jsonLine = call.arguments as String? ?? '';
        try {
          final map = jsonDecode(jsonLine) as Map<String, dynamic>;
          _controller.add(map);
        } catch (_) {
          // ignore malformed
        }
      }
    });
  }

  void dispose() {
    _controller.close();
  }
}
