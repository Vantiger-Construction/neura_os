import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_on_device_asr_config.dart';

void main() {
  const hash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('validates the explicit Zipformer int8 package manifest', () {
    final profile = NeuraOnDeviceAsrProfiles.zipformerEn20230626Int8;
    final manifest = NeuraOnDeviceAsrPackageManifest(
      profileId: profile.id,
      fileSha256: {for (final file in profile.requiredFiles) file: hash},
      licenseEvidence: 'operator_verified_sherpa_onnx_license',
      networkRequired: false,
      createdAtUtc: DateTime.utc(2026, 10, 11),
    );

    manifest.validateProfile(profile);
  });

  test('fails closed for downloads, URL-like paths, and missing files', () {
    final profile = NeuraOnDeviceAsrProfiles.int4Candidate;
    expect(
      () => NeuraOnDeviceAsrPackageManifest(
        profileId: profile.id,
        fileSha256: {for (final file in profile.requiredFiles) file: hash},
        licenseEvidence: 'verified',
        networkRequired: true,
        createdAtUtc: DateTime.utc(2026, 10, 11),
      ),
      throwsFormatException,
    );
    expect(
      () => NeuraOnDeviceAsrPackageManifest(
        profileId: profile.id,
        fileSha256: {'https://example.com/model.onnx': hash},
        licenseEvidence: 'verified',
        networkRequired: false,
        createdAtUtc: DateTime.utc(2026, 10, 11),
      ),
      throwsFormatException,
    );
    expect(
      () => NeuraOnDeviceAsrPackageManifest(
        profileId: profile.id,
        fileSha256: {'tokens.txt': hash},
        licenseEvidence: 'verified',
        networkRequired: false,
        createdAtUtc: DateTime.utc(2026, 10, 11),
      ).validateProfile(profile),
      throwsFormatException,
    );
  });

  test('multilingual profiles require Whisper and the speech detector', () {
    for (final profile in [
      NeuraOnDeviceAsrProfiles.whisperBaseInt8,
      NeuraOnDeviceAsrProfiles.whisperSmallInt8,
    ]) {
      expect(NeuraOnDeviceAsrProfiles.byId(profile.id), same(profile));
      expect(profile.requiredFiles, contains('silero_vad.onnx'));
      NeuraOnDeviceAsrPackageManifest(
        profileId: profile.id,
        fileSha256: {for (final file in profile.requiredFiles) file: hash},
        licenseEvidence: 'operator_verified_whisper_and_silero_licenses',
        networkRequired: false,
        createdAtUtc: DateTime.utc(2026, 11, 27),
      ).validateProfile(profile);
      // Without the speech detector the package is incomplete.
      expect(
        () => NeuraOnDeviceAsrPackageManifest(
          profileId: profile.id,
          fileSha256: {
            for (final file in profile.requiredFiles)
              if (file != 'silero_vad.onnx') file: hash,
          },
          licenseEvidence: 'verified',
          networkRequired: false,
          createdAtUtc: DateTime.utc(2026, 11, 27),
        ).validateProfile(profile),
        throwsFormatException,
      );
    }
  });
}
