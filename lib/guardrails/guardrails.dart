import 'guardrails_types.dart';
import 'guardrails_rules.dart';

class Guardrails {
  final GuardrailRules _rules;
  Guardrails({GuardrailRules? rules}) : _rules = rules ?? GuardrailRules();

  GuardrailDecision evaluate({
    required NeuraContextSnapshot context,
    required NeuraProposal proposal,
  }) {
    final hard = _rules.hardBlock(context, proposal);
    if (hard != null) return hard;

    final shaped = _rules.softShape(context, proposal);
    return shaped ?? GuardrailDecision.allow(proposal);
  }
}
