import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/guardrails/support_resources.dart';
import 'package:neuro_companion/relationships/services/crisis_text_scan.dart';
import 'package:neuro_companion/services/crisis_playbook_surface.dart';

void main() {
  group('CrisisTextScan', () {
    test('flags explicit crisis language', () {
      final scan = CrisisTextScan.of("I don't want to be alive anymore");
      expect(scan.crisis, isTrue);
      expect(scan.distress, isTrue, reason: 'crisis always implies distress');
    });

    test('flags distress without flagging crisis', () {
      final scan = CrisisTextScan.of('I feel completely hopeless lately');
      expect(scan.crisis, isFalse);
      expect(scan.distress, isTrue);
    });

    test('handles a curly apostrophe in crisis language', () {
      final scan = CrisisTextScan.of('I don’t want to be alive anymore');
      expect(scan.crisis, isTrue);
      expect(scan.distress, isTrue);
    });

    test('leaves benign and figurative messages untouched', () {
      expect(CrisisTextScan.of('I had a busy day at work').distress, isFalse);
      expect(
        CrisisTextScan.of("I'm dying to try that new place").crisis,
        isFalse,
      );
    });
  });

  group('CrisisPlaybookSurface', () {
    test('explicit crisis selects the feeling-unsafe playbook', () {
      final scan = CrisisTextScan.of("I don't want to be alive anymore");
      final playbook = CrisisPlaybookSurface.select(scan, 'any text');
      expect(playbook, isNotNull);
      expect(playbook!.id, 'feeling_unsafe');
    });

    test('distress selects a matching playbook', () {
      const message = 'I feel so overwhelmed and hopeless';
      final playbook = CrisisPlaybookSurface.select(
        CrisisTextScan.of(message),
        message,
      );
      expect(playbook, isNotNull);
      expect(playbook!.id, 'overwhelmed');
    });

    test('benign messages surface no playbook', () {
      const message = 'I had a busy day at work';
      expect(
        CrisisPlaybookSurface.select(CrisisTextScan.of(message), message),
        isNull,
      );
    });

    test('formatted block includes the title and grounding steps', () {
      final scan = CrisisTextScan.of("I don't want to be alive anymore");
      final playbook = CrisisPlaybookSurface.select(scan, 'x')!;
      final text = CrisisPlaybookSurface.format(playbook);
      expect(text, contains(playbook.title));
      expect(text, contains('•'));
      expect(text.trim(), isNotEmpty);
    });
  });

  group('SupportResources', () {
    test('US locale receives 988 and immediate-danger guidance', () {
      final message = SupportResources.forLocale('en-US');
      expect(message, contains('988'));
      expect(message, contains('911'));
    });

    test('non-US and unknown locales use the global fallback', () {
      expect(SupportResources.forLocale('en-GB'), contains('local emergency'));
      expect(SupportResources.forLocale(null), contains('local emergency'));
      expect(SupportResources.forLocale('en-GB'), isNot(contains('988')));
    });
  });
}
