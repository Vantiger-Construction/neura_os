import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/support/appointment_summary.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/support_suggestion_choices.dart';

void main() {
  test('request-only and excluded choices are independent and immutable', () {
    final excluded = {GuidedSupportActivity.gentleBreathing};
    final choices =
        SupportSuggestionChoices(onlyWhenAsked: true, excluded: excluded);
    excluded.clear();
    expect(choices.allows(GuidedSupportActivity.grounding, requested: false),
        isFalse);
    expect(choices.allows(GuidedSupportActivity.grounding, requested: true),
        isTrue);
    expect(
        choices.allows(GuidedSupportActivity.gentleBreathing, requested: true),
        isFalse);
    expect(() => choices.excluded.clear(), throwsUnsupportedError);
    expect(SupportSuggestionChoices.fromJson(choices.toJson()).toJson(),
        choices.toJson());
  });

  for (final change in <Map<String, dynamic>>[
    {'version': 2},
    {'scope': 'chat'},
    {'onlyWhenAsked': 'true'},
    {
      'excluded': ['unknown']
    },
    {
      'excluded': ['grounding', 'grounding']
    },
    {'excluded': List.filled(5, 'grounding')},
    {'unexpected': 'private data'},
  ]) {
    test('rejects invalid choices $change', () {
      expect(
          () => SupportSuggestionChoices.fromJson(
              {...SupportSuggestionChoices().toJson(), ...change}),
          throwsFormatException);
    });
  }

  final entry = MoodEntry(
      timestamp: DateTime.utc(2026, 11, 1),
      mood0to10: 4,
      note: 'Synthetic private note',
      energy0to10: 3,
      sleepHours: 6);
  test(
      'summary contains only selected records and omits notes unless requested',
      () {
    final empty = appointmentSummary(
        selected: [], questions: 'Synthetic question', includeNotes: false);
    expect(empty, contains('Synthetic question'));
    expect(empty, isNot(contains('mood 4')));
    final text = appointmentSummary(
        selected: [entry], questions: '', includeNotes: false);
    expect(text, contains('mood 4/10; energy 3/10; sleep 6.0 hours'));
    expect(text, isNot(contains(entry.note)));
    expect(
        appointmentSummary(
            selected: [entry], questions: '', includeNotes: true),
        contains(entry.note));
  });
  test('missing optional values are not represented as zero', () {
    final text = appointmentSummary(selected: [
      MoodEntry(timestamp: DateTime.utc(2026), mood0to10: 5, note: '')
    ], questions: '', includeNotes: false);
    expect(text, isNot(contains('energy')));
    expect(text, isNot(contains('sleep')));
  });
  test(
      'large notes are shortened visibly without splitting Unicode code points',
      () {
    final text = appointmentSummary(selected: [
      MoodEntry(
          timestamp: DateTime.utc(2026),
          mood0to10: 5,
          note: List.filled(501, '🙂').join())
    ], questions: '', includeNotes: true);
    expect(text, contains('[note shortened; review before sharing]'));
    expect('🙂'.allMatches(text).length, 500);
  });
  test('rejects excessive selections and invalid values', () {
    expect(
        () => appointmentSummary(
            selected: List.filled(11, entry),
            questions: '',
            includeNotes: false),
        throwsFormatException);
    expect(
        () => appointmentSummary(
            selected: [], questions: 'x' * 4001, includeNotes: false),
        throwsFormatException);
    expect(
        () => appointmentSummary(selected: [
              MoodEntry(timestamp: DateTime.utc(2026), mood0to10: 99, note: '')
            ], questions: '', includeNotes: false),
        throwsFormatException);
  });
}
