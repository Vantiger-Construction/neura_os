import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';

void main() {
  test('older saved shell preferences receive safe companion defaults', () {
    final prefs = ShellPrefs.fromJson(<String, dynamic>{
      'ambientFx': false,
      'portalFx': true,
      'walkingShimmer': false,
    });
    expect(prefs.companionMotion, NeuraCompanionMotion.subtle);
    expect(prefs.companionScale, NeuraCompanionScale.standard);
    expect(prefs.roomActivityHints, isTrue);
  });

  test('companion customization round-trips through JSON', () {
    final source = ShellPrefs.defaults.copyWith(
      companionMotion: NeuraCompanionMotion.expressive,
      companionScale: NeuraCompanionScale.large,
      roomActivityHints: false,
    );
    final restored = ShellPrefs.fromJson(source.toJson());
    expect(restored.companionMotion, NeuraCompanionMotion.expressive);
    expect(restored.companionScale, NeuraCompanionScale.large);
    expect(restored.roomActivityHints, isFalse);
  });
}
