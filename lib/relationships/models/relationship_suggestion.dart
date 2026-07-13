
class RelationshipSuggestion {
  final String title;
  final String description;
  final String actionLabel;
  final List<String> reasons;

  const RelationshipSuggestion({
    required this.title,
    required this.description,
    required this.actionLabel,
    this.reasons = const [],
  });
}
