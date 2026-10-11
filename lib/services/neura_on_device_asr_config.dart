final class NeuraOnDeviceAsrProfile {
  const NeuraOnDeviceAsrProfile({
    required this.id,
    required this.requiredFiles,
    required this.description,
  });

  final String id;
  final List<String> requiredFiles;
  final String description;
}

final class NeuraOnDeviceAsrPackageManifest {
  NeuraOnDeviceAsrPackageManifest({
    required this.profileId,
    required this.fileSha256,
    required this.licenseEvidence,
    required this.networkRequired,
    required this.createdAtUtc,
  }) {
    if (!createdAtUtc.isUtc) {
      throw const FormatException('ASR manifest timestamp must be UTC.');
    }
    if (networkRequired) {
      throw const FormatException(
        'ASR model packages must not require network.',
      );
    }
    if (licenseEvidence.trim().isEmpty) {
      throw const FormatException('ASR model license evidence is required.');
    }
    for (final entry in fileSha256.entries) {
      _requirePlainFilename(entry.key);
      if (!_sha256.hasMatch(entry.value)) {
        throw FormatException('Invalid SHA-256 for ${entry.key}.');
      }
    }
  }

  factory NeuraOnDeviceAsrPackageManifest.fromJson(Map<String, dynamic> json) {
    final files = Map<String, dynamic>.from(json['fileSha256'] as Map);
    return NeuraOnDeviceAsrPackageManifest(
      profileId: json['profileId'] as String,
      fileSha256: files.map((key, value) => MapEntry(key, value as String)),
      licenseEvidence: json['licenseEvidence'] as String,
      networkRequired: json['networkRequired'] as bool? ?? true,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
    );
  }

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  final String profileId;
  final Map<String, String> fileSha256;
  final String licenseEvidence;
  final bool networkRequired;
  final DateTime createdAtUtc;

  void validateProfile(NeuraOnDeviceAsrProfile profile) {
    if (profileId != profile.id) {
      throw const FormatException('ASR manifest profile mismatch.');
    }
    final expected = profile.requiredFiles.toSet();
    final actual = fileSha256.keys.toSet();
    if (actual.length != expected.length ||
        !actual.containsAll(expected) ||
        !expected.containsAll(actual)) {
      throw const FormatException('ASR manifest file set mismatch.');
    }
  }

  static void _requirePlainFilename(String value) {
    if (value.trim() != value ||
        value.isEmpty ||
        value.contains('/') ||
        value.contains(r'\') ||
        value.contains(':') ||
        value.codeUnits.any((unit) => unit < 0x21 || unit == 0x7f)) {
      throw const FormatException(
        'ASR manifest paths must be plain filenames.',
      );
    }
  }
}

abstract final class NeuraOnDeviceAsrProfiles {
  static const int4Candidate = NeuraOnDeviceAsrProfile(
    id: 'int4',
    description: 'Candidate int4 transducer convention; not release-validated.',
    requiredFiles: [
      'encoder.int4.onnx',
      'decoder.int4.onnx',
      'joiner.int4.onnx',
      'tokens.txt',
    ],
  );

  static const zipformerEn20230626Int8 = NeuraOnDeviceAsrProfile(
    id: 'zipformer-en-2023-06-26-int8',
    description: 'Sherpa-ONNX English streaming Zipformer int8 profile.',
    requiredFiles: [
      'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
      'decoder-epoch-99-avg-1-chunk-16-left-128.onnx',
      'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
      'tokens.txt',
    ],
  );

  static const all = [int4Candidate, zipformerEn20230626Int8];

  static NeuraOnDeviceAsrProfile byId(String id) => all.firstWhere(
    (profile) => profile.id == id,
    orElse: () => throw const FormatException('Unknown ASR profile.'),
  );
}
