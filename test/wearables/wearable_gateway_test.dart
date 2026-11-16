import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/wearables/wearable_gateway.dart';
import 'package:neuro_companion/wearables/wearable_snapshot.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('neura/health_connect');
  const gateway = HealthConnectGateway();
  final calls = <MethodCall>[];
  setUp(() => calls.clear());
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('unsupported platform returns unavailable, never sample health values',
      () async {
    expect(await gateway.available(), isFalse);
    await gateway.cancel('0' * 32);
    await expectLater(gateway.read('0' * 32, {WearableMetric.steps}),
        throwsA(isA<MissingPluginException>()));
  });

  test('permission approval and settings never dispatch a data read', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return switch (call.method) {
        'availability' => {'available': true},
        'permissions' => ['steps', 'unknown'],
        'managePermissions' => true,
        _ => null,
      };
    });
    expect(await gateway.available(), isTrue);
    await gateway.requestPermissions({WearableMetric.steps});
    expect(await gateway.permissions(), {WearableMetric.steps});
    expect(await gateway.managePermissions(), isTrue);
    expect(calls.any((call) => call.method == 'read'), isFalse);
    expect(calls[1].arguments, {
      'metrics': ['steps']
    });
  });

  test('foreground request sends exactly selected types and matching cancel ID',
      () async {
    final id = HealthConnectGateway.requestId();
    expect(id, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(HealthConnectGateway.requestId(), isNot(id));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      final now = DateTime.now().toUtc();
      return call.method == 'read'
          ? {
              'schema': 1,
              'fromMs': now
                  .subtract(const Duration(hours: 24))
                  .millisecondsSinceEpoch,
              'toMs': now.millisecondsSinceEpoch,
              'metrics': {
                'steps': {'status': 'no_data'}
              },
            }
          : null;
    });
    final snapshot = await gateway.read(id, {WearableMetric.steps});
    expect(snapshot.readings.keys, [WearableMetric.steps]);
    await gateway.cancel(id);
    expect(calls[0].arguments, {
      'id': id,
      'metrics': ['steps']
    });
    expect(calls[1].arguments, {'id': id});
  });
}
