import '../care/models/crisis_playbook.dart';
import '../care/services/crisis_playbook_service.dart';
import '../relationships/services/crisis_text_scan.dart';

/// Selects and formats existing grounding playbooks for the chat guardrail
/// path. This adds no diagnosis or new clinical content.
class CrisisPlaybookSurface {
  static CrisisPlaybook? select(CrisisTextScan scan, String message) {
    final service = CrisisPlaybookService.instance;
    if (scan.crisis) {
      return service.findById('feeling_unsafe') ??
          service.findByKeyword(message);
    }
    if (scan.distress) {
      return service.findByKeyword(message) ?? service.findById('overwhelmed');
    }
    return null;
  }

  static String format(CrisisPlaybook playbook, {int maxSteps = 4}) {
    final buffer = StringBuffer()
      ..writeln(
        'A few things that might help right now — ${playbook.title}:',
      );
    for (final step in playbook.steps.take(maxSteps)) {
      buffer.writeln('• $step');
    }
    return buffer.toString().trimRight();
  }
}
