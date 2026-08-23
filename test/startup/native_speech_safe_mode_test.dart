import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_speech_to_text_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native speech recognition stays disabled in Safe Mode', () async {
    final originalSafeMode = SafeBoot.instance.safeMode.value;
    addTearDown(() {
      SafeBoot.instance.safeMode.value = originalSafeMode;
    });

    SafeBoot.instance.safeMode.value = true;

    expect(NeuraSpeechToTextService.instance.listeningAllowed, isFalse);
    expect(
      await NeuraSpeechToTextService.instance.startRecording(),
      isFalse,
    );
  });
}
