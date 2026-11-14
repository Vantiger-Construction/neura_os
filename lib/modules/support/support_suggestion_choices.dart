import 'guided_support_activity.dart';

/// Explicit controls for the guided-support suggestion only, never inferred traits.
class SupportSuggestionChoices {
  SupportSuggestionChoices({
    this.onlyWhenAsked = false,
    Set<GuidedSupportActivity> excluded = const {},
  }) : excluded = Set.unmodifiable(excluded);

  final bool onlyWhenAsked;
  final Set<GuidedSupportActivity> excluded;

  bool allows(GuidedSupportActivity activity, {required bool requested}) =>
      !excluded.contains(activity) && (!onlyWhenAsked || requested);

  Map<String, dynamic> toJson() => {
        'version': 1,
        'scope': 'guided_support_suggestions',
        'onlyWhenAsked': onlyWhenAsked,
        'excluded': [
          for (final activity in GuidedSupportActivity.values)
            if (excluded.contains(activity)) activity.name,
        ],
      };

  factory SupportSuggestionChoices.fromJson(Map<String, dynamic> json) {
    final names = json['excluded'];
    if (json.length != 4 ||
        json['version'] != 1 ||
        json['scope'] != 'guided_support_suggestions' ||
        json['onlyWhenAsked'] is! bool ||
        names is! List ||
        names.length > GuidedSupportActivity.values.length) {
      throw const FormatException('Invalid support suggestion choices.');
    }
    final excluded = <GuidedSupportActivity>{};
    for (final name in names) {
      final matches = GuidedSupportActivity.values.where((a) => a.name == name);
      if (matches.length != 1 || !excluded.add(matches.single)) {
        throw const FormatException('Invalid or repeated activity choice.');
      }
    }
    return SupportSuggestionChoices(
        onlyWhenAsked: json['onlyWhenAsked'] as bool, excluded: excluded);
  }
}
