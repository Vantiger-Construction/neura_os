/// Rules for suppressing certain behaviors in specific contexts
class SuppressionRules {
  final Map<String, bool> _suppressions = {};
  
  void suppress(String behavior) {
    _suppressions[behavior] = true;
  }
  
  void allow(String behavior) {
    _suppressions[behavior] = false;
  }
  
  bool isSuppressed(String behavior) {
    return _suppressions[behavior] ?? false;
  }
}
