import 'dart:convert';

import 'package:http/http.dart' as http;

/// Info about a newer release, when one exists.
class AvailableUpdate {
  final String tag;
  final String htmlUrl;
  final String? notes;
  final String? artifactSha256;
  final bool userInitiatedInstallOnly;

  const AvailableUpdate({
    required this.tag,
    required this.htmlUrl,
    this.notes,
    this.artifactSha256,
    this.userInitiatedInstallOnly = true,
  });
}

/// Checks a public release manifest for a newer build than the one running.
///
/// The client never installs automatically and never embeds a private-repo
/// token. A distributed build must provide RELEASE_MANIFEST_URL and BUILD_TAG
/// at build time; otherwise update checks are inert.
class UpdateCheckService {
  UpdateCheckService._({http.Client? client})
      : _client = client ?? http.Client(),
        _configuredCurrentTag = _currentTag,
        _configuredManifestUrl = _manifestUrl;
  UpdateCheckService.forTesting({
    required http.Client client,
    String currentTag = '',
    String manifestUrl = '',
  })  : _client = client,
        _configuredCurrentTag = currentTag,
        _configuredManifestUrl = manifestUrl;

  static final UpdateCheckService instance = UpdateCheckService._();

  /// This build's own release tag, baked in at build time via
  /// --dart-define=BUILD_TAG=beta-win64-YYYY-MM-DD (matching the existing
  /// tag convention). Empty by default, meaning update-checking is inert
  /// until a real value is supplied at build time - same pattern as
  /// ANTHROPIC_API_KEY only being "configured" when actually set.
  static const _currentTag = String.fromEnvironment('BUILD_TAG');
  static const _manifestUrl = String.fromEnvironment('RELEASE_MANIFEST_URL');

  final http.Client _client;
  final String _configuredCurrentTag;
  final String _configuredManifestUrl;
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  Future<AvailableUpdate?> checkForUpdate() async {
    if (_configuredCurrentTag.isEmpty || _configuredManifestUrl.isEmpty) {
      return null;
    }
    try {
      final response = await _client.get(
        Uri.parse(_configuredManifestUrl),
        headers: {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['schema'] != 1) return null;
      final latestTag = json['latestTag'] as String?;
      final htmlUrl = json['htmlUrl'] as String?;
      final artifactSha256 = json['artifactSha256'] as String?;
      final userInitiated = json['userInitiatedInstallOnly'] as bool? ?? true;
      if (latestTag == null || htmlUrl == null) return null;
      if (!userInitiated) return null;
      if (artifactSha256 == null || !_sha256.hasMatch(artifactSha256)) {
        return null;
      }
      if (latestTag == _configuredCurrentTag) return null;

      return AvailableUpdate(
        tag: latestTag,
        htmlUrl: htmlUrl,
        notes: json['notes'] as String?,
        artifactSha256: artifactSha256,
        userInitiatedInstallOnly: userInitiated,
      );
    } catch (_) {
      // Network error, private-repo 404, malformed response - all treated
      // the same: no update info available right now, not a fatal error.
      return null;
    }
  }
}
