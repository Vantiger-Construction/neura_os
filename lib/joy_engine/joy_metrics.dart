import 'joy_types.dart';

/// Local-only metrics hook (wire into Memory Graph if desired).
class JoyMetrics {
  Future<void> logResult(JoyMoment moment, {required String result}) async {
    // TODO: integrate with encrypted memory graph:
    // createNode(type: 'JoyMoment', payload: {moment.id, result}, outcome: result)
  }
}
