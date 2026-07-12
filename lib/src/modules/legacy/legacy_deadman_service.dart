import 'dart:convert';
import 'package:flutter/material.dart';
import 'legacy_delivery_service.dart';
import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';
import '../../../startup/neura_prefs_cache.dart';

class LegacyDeadmanSettings {
  final bool enabled;
  final int checkInIntervalDays;
  final int graceDays;
  final int lastCheckInEpochMs;
  final List<String> capsuleIdsToRelease;

  const LegacyDeadmanSettings({
    required this.enabled,
    required this.checkInIntervalDays,
    required this.graceDays,
    required this.lastCheckInEpochMs,
    required this.capsuleIdsToRelease,
  });

  DateTime get lastCheckInAt =>
      DateTime.fromMillisecondsSinceEpoch(lastCheckInEpochMs);

  LegacyDeadmanSettings copyWith({
    bool? enabled,
    int? checkInIntervalDays,
    int? graceDays,
    int? lastCheckInEpochMs,
    List<String>? capsuleIdsToRelease,
  }) {
    return LegacyDeadmanSettings(
      enabled: enabled ?? this.enabled,
      checkInIntervalDays: checkInIntervalDays ?? this.checkInIntervalDays,
      graceDays: graceDays ?? this.graceDays,
      lastCheckInEpochMs: lastCheckInEpochMs ?? this.lastCheckInEpochMs,
      capsuleIdsToRelease: capsuleIdsToRelease ?? this.capsuleIdsToRelease,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'checkInIntervalDays': checkInIntervalDays,
        'graceDays': graceDays,
        'lastCheckInEpochMs': lastCheckInEpochMs,
        'capsuleIdsToRelease': capsuleIdsToRelease,
      };

  factory LegacyDeadmanSettings.fromMap(Map<String, dynamic> map) {
    List<String> list(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      return const [];
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return LegacyDeadmanSettings(
      enabled: map['enabled'] == true,
      checkInIntervalDays:
          int.tryParse(map['checkInIntervalDays']?.toString() ?? '') ?? 30,
      graceDays: int.tryParse(map['graceDays']?.toString() ?? '') ?? 7,
      lastCheckInEpochMs:
          int.tryParse(map['lastCheckInEpochMs']?.toString() ?? '') ?? now,
      capsuleIdsToRelease: list(map['capsuleIdsToRelease']),
    );
  }

  static LegacyDeadmanSettings defaults() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return LegacyDeadmanSettings(
      enabled: false,
      checkInIntervalDays: 30,
      graceDays: 7,
      lastCheckInEpochMs: now,
      capsuleIdsToRelease: const [],
    );
  }
}

class LegacyDeadmanService {
  LegacyDeadmanService._();

  static final LegacyDeadmanService instance = LegacyDeadmanService._();

  static const String _kKey = 'neura_legacy_deadman_settings_v1';

  Future<LegacyDeadmanSettings> load() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) {
      return LegacyDeadmanSettings.defaults();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return LegacyDeadmanSettings.defaults();
      return LegacyDeadmanSettings.fromMap(decoded.cast<String, dynamic>());
    } catch (_) {
      return LegacyDeadmanSettings.defaults();
    }
  }

  Future<void> save(LegacyDeadmanSettings settings) async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_kKey, jsonEncode(settings.toMap()));
  }

  Future<void> markCheckedInNow() async {
    final s = await load();
    await save(
        s.copyWith(lastCheckInEpochMs: DateTime.now().millisecondsSinceEpoch));
  }

  /// Returns true if the user is overdue.
  Future<bool> isOverdue() async {
    final s = await load();
    if (!s.enabled) return false;

    final nextDue = s.lastCheckInAt
        .add(Duration(days: s.checkInIntervalDays + s.graceDays));
    return DateTime.now().isAfter(nextDue);
  }

  /// Called on app start. If overdue, prompts the user to check in.
  Future<void> maybePromptOnStartup(BuildContext context) async {
    final s = await load();
    if (!s.enabled) return;

    final dueAt = s.lastCheckInAt
        .add(Duration(days: s.checkInIntervalDays + s.graceDays));
    if (DateTime.now().isBefore(dueAt)) return;

    // Build a quick preview list of capsules.
    final all = await LegacyVaultService.instance.listCapsules();
    final selected = s.capsuleIdsToRelease.isEmpty
        ? all
            .where((c) => c.deliveryEnabled && c.deliveryTrigger == 'deadman')
            .toList()
        : all.where((c) => s.capsuleIdsToRelease.contains(c.id)).toList();

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Legacy Guard Check‑In'),
        content: Text(
          "It's been a while since your last check‑in (last: ${s.lastCheckInAt.toLocal().toString().substring(0, 16)}).\n\n"
          "If you're here: tap \"I'm Alive\".\n"
          'If you want: Neura can prepare delivery packets for your selected capsules.\n\n'
          'Capsules queued: ${selected.length}.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'alive'),
              child: const Text("I'm Alive")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, 'release'),
              child: const Text('Prepare Packets')),
        ],
      ),
    );

    if (action == 'alive') {
      await markCheckedInNow();
      return;
    }

    if (action == 'release') {
      await _preparePacketsFlow(context, selected);
    }
  }

  Future<void> _preparePacketsFlow(
      BuildContext context, List<LegacyCapsule> capsules) async {
    if (capsules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No capsules selected for Legacy Guard release.')),
      );
      return;
    }

    final decrypt = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decrypt encrypted capsules?'),
        content: const Text(
          'If you decrypt, recipients can read without needing your passphrase — but you must enter passphrases now.\n\n'
          "If you don't decrypt, Neura will export encrypted packets (still safe; needs passphrase later).",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Encrypted')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Decrypt Now')),
        ],
      ),
    );

    final packets = <String>[];

    for (final c in capsules) {
      try {
        final file = await LegacyDeliveryService.instance.createDeliveryPacket(
          capsule: c,
          preferFormat: c.deliveryFormat,
          decryptIfPossible: decrypt == true,
          context: context,
        );
        packets.add(file.path);
      } catch (_) {
        // continue
      }
    }

    if (packets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No packets created (passphrase failures or missing data).')),
      );
      return;
    }

    await LegacyDeliveryService.instance.shareFiles(
      filePaths: packets,
      text: 'Legacy Guard packets (${packets.length})',
    );
  }
}
