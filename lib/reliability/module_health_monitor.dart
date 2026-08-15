import 'package:flutter/foundation.dart';

enum NeuraModuleStatus { unknown, starting, healthy, degraded, failed, skipped }

@immutable
class NeuraModuleHealth {
  const NeuraModuleHealth({
    required this.name,
    required this.status,
    required this.updatedAt,
    this.duration,
    this.detail,
    this.remedy,
  });

  final String name;
  final NeuraModuleStatus status;
  final DateTime updatedAt;
  final Duration? duration;
  final String? detail;
  final String? remedy;

  bool get needsAttention =>
      status == NeuraModuleStatus.degraded ||
      status == NeuraModuleStatus.failed;
}

class ModuleHealthMonitor extends ChangeNotifier {
  ModuleHealthMonitor._();
  static final ModuleHealthMonitor instance = ModuleHealthMonitor._();

  final Map<String, NeuraModuleHealth> _modules = {};

  List<NeuraModuleHealth> get snapshot {
    final values = _modules.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(values);
  }

  void starting(String name) => _set(name, NeuraModuleStatus.starting);

  void healthy(String name, {Duration? duration, String? detail}) => _set(
        name,
        NeuraModuleStatus.healthy,
        duration: duration,
        detail: detail,
      );

  void degraded(String name, {String? detail, String? remedy}) => _set(
        name,
        NeuraModuleStatus.degraded,
        detail: detail,
        remedy: remedy,
      );

  void failed(String name, Object error, {String? remedy}) => _set(
        name,
        NeuraModuleStatus.failed,
        detail: error.toString(),
        remedy: remedy ?? 'Restart Neura in Safe Mode and review Diagnostics.',
      );

  void skipped(String name, String reason) => _set(
        name,
        NeuraModuleStatus.skipped,
        detail: reason,
      );

  void resetAfterDataWipe() {
    _modules.clear();
    notifyListeners();
  }

  void _set(
    String name,
    NeuraModuleStatus status, {
    Duration? duration,
    String? detail,
    String? remedy,
  }) {
    _modules[name] = NeuraModuleHealth(
      name: name,
      status: status,
      updatedAt: DateTime.now().toUtc(),
      duration: duration,
      detail: detail,
      remedy: remedy,
    );
    notifyListeners();
  }
}
