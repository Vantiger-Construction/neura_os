import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/module_health_monitor.dart';

void main() {
  test('module health transitions retain actionable details', () {
    final monitor = ModuleHealthMonitor.instance;
    monitor.starting('test-module');
    monitor.degraded(
      'test-module',
      detail: 'dependency unavailable',
      remedy: 'Install dependency and retry.',
    );

    final module = monitor.snapshot.singleWhere((m) => m.name == 'test-module');
    expect(module.status, NeuraModuleStatus.degraded);
    expect(module.needsAttention, isTrue);
    expect(module.remedy, contains('retry'));
  });
}
