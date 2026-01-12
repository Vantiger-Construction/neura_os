import '../behavior/behavior_engine.dart';
import '../behavior/context_snapshot.dart';
import '../presence/neura_presence_controller.dart';
import 'neura_object.dart';

class ObjectInteractionEngine {
  final BehaviorEngine behavior;
  final NeuraPresenceController presence;

  ObjectInteractionEngine({
    required this.behavior,
    required this.presence,
  });

  Future<void> interact(NeuraObject object) async {
    final decision = await behavior.decideNext(
      context: ContextSnapshot(
        now: DateTime.now(),
        location: object.id,
        userActive: true,
      ),
    );
    presence.applyDecision(decision);
  }
}
