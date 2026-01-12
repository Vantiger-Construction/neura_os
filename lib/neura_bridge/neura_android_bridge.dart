import 'dart:convert';
import 'package:flutter/services.dart';

class NeuraAndroidBridge {
  static const MethodChannel _ch = MethodChannel('neura/unity');

  Future<void> send(Map<String, dynamic> msg) async {
    await _ch.invokeMethod('sendToUnity', {'json': jsonEncode(msg)});
  }
}
