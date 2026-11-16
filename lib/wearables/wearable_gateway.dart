import 'dart:math';
import 'package:flutter/services.dart';
import 'wearable_snapshot.dart';

abstract class WearableGateway {
  Future<bool> available();
  Future<Set<WearableMetric>> permissions();
  Future<void> requestPermissions(Set<WearableMetric> metrics);
  Future<WearableSnapshot> read(String id, Set<WearableMetric> metrics);
  Future<bool> managePermissions();
  Future<void> cancel(String id);
}

class HealthConnectGateway implements WearableGateway {
  const HealthConnectGateway(
      {this.channel = const MethodChannel('neura/health_connect')});
  final MethodChannel channel;
  static String requestId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  Future<bool> available() async {
    try {
      return (await channel.invokeMapMethod<String, Object?>(
              'availability'))?['available'] ==
          true;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Set<WearableMetric>> permissions() async {
    final result = await channel.invokeListMethod<String>('permissions');
    return WearableMetric.values
        .where((m) => result?.contains(m.key) ?? false)
        .toSet();
  }

  @override
  Future<void> requestPermissions(Set<WearableMetric> metrics) async {
    await channel.invokeMethod<Object?>(
        'requestPermissions', {'metrics': metrics.map((m) => m.key).toList()});
  }

  @override
  Future<WearableSnapshot> read(String id, Set<WearableMetric> metrics) async {
    final payload = await channel.invokeMethod<Object?>(
        'read', {'id': id, 'metrics': metrics.map((m) => m.key).toList()});
    return WearableSnapshot.fromPlatform(payload,
        requested: metrics, now: DateTime.now());
  }

  @override
  Future<bool> managePermissions() async =>
      await channel.invokeMethod<bool>('managePermissions') ?? false;
  @override
  Future<void> cancel(String id) async {
    try {
      await channel.invokeMethod<void>('cancel', {'id': id});
    } on MissingPluginException {/* No native read exists on this platform. */}
  }
}
