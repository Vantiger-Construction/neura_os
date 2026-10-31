import 'dart:convert';

import 'package:flutter/services.dart';

/// User-selected context caps; neither profile changes model or permissions.
enum NeuraOfflineBudget {
  compact('Compact', 750),
  standard('Standard', 1500);

  const NeuraOfflineBudget(this.label, this.contextBytes);
  final String label;
  final int contextBytes;

  /// Preserve the newest user turn and whole older turns within the byte cap.
  /// Never truncate user text or include an orphaned assistant response.
  List<Map<String, dynamic>> retain(List<Map<String, dynamic>> messages,
      {String threadContext = ''}) {
    if (messages.isEmpty || messages.last['role'] != 'user') {
      throw StateError('An offline request needs a new user message.');
    }
    final newest = messages.last['content'];
    if (newest is! String) throw StateError('Offline chat accepts text only.');
    // The brief shares the existing budget. Never displace the newest request
    // or expand native context/RAM limits to keep it.
    final threadBytes = utf8.encode(threadContext).length;
    final useThread = threadContext.isNotEmpty &&
        threadBytes <= 450 &&
        threadBytes + utf8.encode(newest).length <= contextBytes;
    var bytes = useThread ? threadBytes : 0;
    final retained = <Map<String, dynamic>>[];
    for (final message in messages.reversed.take(useThread ? 7 : 8)) {
      final text = message['content'];
      if (text is! String ||
          (message['role'] != 'user' && message['role'] != 'assistant')) {
        throw StateError('Offline chat accepts text turns only.');
      }
      final size = utf8.encode(text).length;
      if (bytes + size > contextBytes) {
        if (retained.isEmpty) {
          throw StateError('Shorten this message or choose Standard context.');
        }
        break;
      }
      bytes += size;
      retained.insert(0, Map<String, dynamic>.of(message));
    }
    while (retained.first['role'] != 'user') {
      retained.removeAt(0);
    }
    if (useThread) {
      retained.insert(0, {'role': 'user', 'content': threadContext});
    }
    return retained;
  }
}

/// Content-free RAM snapshot, requested explicitly. No model or network work.
class NeuraOfflineMemory {
  const NeuraOfflineMemory(this.totalMiB, this.availableMiB);
  final int totalMiB;
  final int availableMiB;
  bool get admitted => totalMiB >= 7168 && availableMiB >= 3584;

  static Future<NeuraOfflineMemory?> read({
    MethodChannel channel = const MethodChannel(
      'neura/engine_synthetic_session',
    ),
  }) async {
    try {
      final values = await channel.invokeMapMethod<String, dynamic>(
        'readOfflineMemory',
      );
      if (values == null || values.length != 2) return null;
      final total = values['totalMiB'];
      final available = values['availableMiB'];
      if (total is! int ||
          available is! int ||
          total <= 0 ||
          available < 0 ||
          available > total) {
        return null;
      }
      return NeuraOfflineMemory(total, available);
    } catch (_) {
      return null;
    }
  }
}
