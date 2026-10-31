import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Manual transfer of one user-reviewed plan. No chat, notes, identifiers,
/// device trust, execution approvals or journals are serialized.
class NeuraTaskSnapshot {
  NeuraTaskSnapshot(
      {required this.goal,
      required List<String> steps,
      required Set<int> completed})
      : steps = List.unmodifiable(steps),
        completed = Set.unmodifiable(completed) {
    if (goal.trim().isEmpty ||
        goal.length > 200 ||
        steps.isEmpty ||
        steps.length > 8 ||
        steps.any((s) => s.trim().isEmpty || s.length > 160) ||
        completed.any((i) => i < 0 || i >= steps.length) ||
        [goal, ...steps].any((s) => s.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
      throw const FormatException('Invalid task snapshot.');
    }
  }
  final String goal;
  final List<String> steps;
  final Set<int> completed;
}

class NeuraTaskPacket {
  const NeuraTaskPacket(this.packet, this.key);
  final String packet;
  final String key;
}

class NeuraTaskTransfer {
  static final _cipher = AesGcm.with256bits();
  static final _aad = utf8.encode('neura.reviewed-task.v1');
  static const maxPacketCharacters = 16000;

  static Future<NeuraTaskPacket> seal(NeuraTaskSnapshot snapshot,
      {DateTime? now}) async {
    final issued = (now ?? DateTime.now()).toUtc();
    final key = await _cipher.newSecretKey();
    final bytes = utf8.encode(jsonEncode({
      'v': 1,
      'issued': issued.millisecondsSinceEpoch,
      'expires': issued.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      'goal': snapshot.goal,
      'steps': snapshot.steps,
      'completed': snapshot.completed.toList()..sort(),
    }));
    final box = await _cipher.encrypt(bytes, secretKey: key, aad: _aad);
    return NeuraTaskPacket(base64UrlEncode(box.concatenation()),
        base64UrlEncode(await key.extractBytes()));
  }

  static Future<NeuraTaskSnapshot> open(String packet, String key,
      {DateTime? now}) async {
    if (packet.length > maxPacketCharacters ||
        packet.isEmpty ||
        key.length != 44) {
      throw const FormatException('Invalid task packet or key.');
    }
    final keyBytes = base64Url.decode(key);
    if (keyBytes.length != 32) throw const FormatException('Invalid key.');
    final box = SecretBox.fromConcatenation(base64Url.decode(packet),
        nonceLength: 12, macLength: 16);
    final bytes =
        await _cipher.decrypt(box, secretKey: SecretKey(keyBytes), aad: _aad);
    if (bytes.length > 8000) throw const FormatException('Task is too large.');
    final value = jsonDecode(utf8.decode(bytes));
    const fields = {'v', 'issued', 'expires', 'goal', 'steps', 'completed'};
    if (value is! Map<String, dynamic> ||
        value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        value['v'] != 1 ||
        value['issued'] is! int ||
        value['expires'] is! int ||
        value['goal'] is! String ||
        value['steps'] is! List ||
        value['completed'] is! List ||
        !(value['steps'] as List).every((v) => v is String) ||
        !(value['completed'] as List).every((v) => v is int)) {
      throw const FormatException('Invalid task data.');
    }
    final current = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final issued = value['issued'] as int;
    final expires = value['expires'] as int;
    if (issued > current ||
        expires <= current ||
        expires <= issued ||
        expires - issued > const Duration(minutes: 30).inMilliseconds) {
      throw const FormatException(
          'Task packet expired or device clocks disagree.');
    }
    final completed = (value['completed'] as List).cast<int>();
    if (completed.toSet().length != completed.length) {
      throw const FormatException('Duplicate progress.');
    }
    return NeuraTaskSnapshot(
        goal: value['goal'] as String,
        steps: (value['steps'] as List).cast<String>(),
        completed: completed.toSet());
  }
}
