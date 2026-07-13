
class SituationPlaybook {
  final String id;
  final String name;
  final List<String> triggerKeywords;
  final List<String> steps;

  SituationPlaybook({
    required this.id,
    required this.name,
    required this.triggerKeywords,
    required this.steps,
  });
}
