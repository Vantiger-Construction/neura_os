import '../../modules/mood/mood_models.dart';
import '../../modules/support/appointment_summary.dart';
import 'clinic_contact_draft.dart';

/// Deterministic, selected self-reports. No model, private-store access, inferred
/// diagnosis, automatic recipient selection or transport is involved.
String clinicReport({
  required ClinicContactDraft draft,
  required List<MoodEntry> selected,
  required bool includeNotes,
  required DateTime preparedAt,
}) {
  final summary = appointmentSummary(
      selected: selected, questions: draft.notes, includeNotes: includeNotes);
  final report = 'To: ${draft.clinicName.trim()}\n'
      'From: ${draft.personName.trim()}\n'
      'Request: ${draft.purpose.label}\n'
      'Prepared: ${preparedAt.toLocal().toIso8601String()} (local device time)\n\n'
      '$summary\n\n'
      'Prepared with Neura, an AI assistant, and reviewed by the person. '
      'Please respond through your usual patient contact process.';
  if (report.length > 12000) {
    throw const FormatException(
        'The report is too long. Choose fewer check-ins or shorter notes.');
  }
  return report;
}
