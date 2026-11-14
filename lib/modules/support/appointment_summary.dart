import '../mood/mood_models.dart';

String appointmentSummary(
    {required List<MoodEntry> selected,
    required String questions,
    required bool includeNotes}) {
  if (selected.length > 10 || questions.length > 4000) {
    throw const FormatException(
        'Choose at most ten check-ins and shorter questions.');
  }
  final lines = <String>[
    'My appointment notes',
    'Prepared and selected by me. These are self-reports, not a diagnosis.',
    '',
    'Questions or topics I want to discuss:',
    questions.trim().isEmpty
        ? '(I have not added questions.)'
        : questions.trim(),
    '',
    'Check-ins I chose to include (${selected.length}):',
  ];
  for (final item in selected) {
    if (item.mood0to10 < 0 || item.mood0to10 > 10) {
      throw const FormatException(
          'A selected check-in has an invalid mood value.');
    }
    lines.add(
        '${item.timestamp.toLocal().toIso8601String()} (local device time): '
        'mood ${item.mood0to10}/10'
        '${item.energy0to10 == null ? '' : '; energy ${item.energy0to10}/10'}'
        '${item.sleepHours == null ? '' : '; sleep ${item.sleepHours} hours'}');
    if (includeNotes && item.note.trim().isNotEmpty) {
      final runes = item.note.runes.take(501).toList();
      lines.add('My note: ${String.fromCharCodes(runes.take(500))}'
          '${runes.length > 500 ? ' [note shortened; review before sharing]' : ''}');
    }
  }
  lines.add(
      '\nI can edit or remove any part before sharing. Nothing is sent automatically.');
  final result = lines.join('\n');
  if (result.length > 12000) {
    throw const FormatException(
        'The summary is too long. Choose fewer check-ins.');
  }
  return result;
}
