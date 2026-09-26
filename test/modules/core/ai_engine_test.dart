import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/core/ai_engine.dart';

void main() {
  final core = NeuraAICore.instance;

  test('offline planning stays advisory and room-aware', () {
    final reply = core.respondDetailed(
      'Help me make a plan',
      roomId: 'reflection_bay',
    );
    expect(reply.intent, 'small_plan');
    expect(reply.text, contains('Reflection Bay'));
    expect(reply.text, contains('separate review and approval'));
    expect(reply.suggestedSteps, hasLength(3));
  });

  test('offline image response does not pretend to inspect pixels', () {
    final reply = core.respondDetailed('What is this?', imageAttached: true);
    expect(reply.intent, 'image_unavailable_offline');
    expect(reply.text, contains('cannot inspect'));
  });

  test('urgent safety language points to immediate human help', () {
    final reply = core.respondDetailed('I want to hurt myself');
    expect(reply.intent, 'urgent_safety');
    expect(reply.text, contains('emergency services'));
    expect(reply.suggestedSteps, isNotEmpty);
  });
}
