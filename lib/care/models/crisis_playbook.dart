class CrisisPlaybook {
  final String id;
  final String title;
  final String description;
  final List<String> steps;
  final List<String> tags;

  const CrisisPlaybook({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
    required this.tags,
  });
}
