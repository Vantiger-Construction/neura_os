import 'dart:convert';

import 'package:http/http.dart' as http;

/// Info about a newer release, when one exists.
class AvailableUpdate {
  final String tag;
  final String htmlUrl;
  final String? notes;

  const AvailableUpdate({required this.tag, required this.htmlUrl, this.notes});
}

/// Checks GitHub Releases for a newer build than the one currently running.
///
/// IMPORTANT LIMITATION: `Vantiger1/neura_os` is a private repository, and
/// this hits GitHub's public REST API unauthenticated (baking any token
/// with read access to a private repo into a distributed client binary
/// would let anyone who extracts it browse the whole private source tree -
/// not an acceptable tradeoff just for update-checking). Unauthenticated
/// requests to a private repo's releases endpoint return 404, so as long as
/// the repo stays private this will simply never find an update - it fails
/// silently (same code path as a network error), not with a crash or a
/// false result. To make this actually work, either make the repo public,
/// or publish version info somewhere unauthenticated (e.g. a tiny public
/// repo/gist/Pages endpoint just for a version file) and point [_apiUrl] at
/// that instead.
class UpdateCheckService {
  UpdateCheckService._();
  static final UpdateCheckService instance = UpdateCheckService._();

  static const _apiUrl = 'https://api.github.com/repos/Vantiger1/neura_os/releases/latest';

  /// This build's own release tag, baked in at build time via
  /// --dart-define=BUILD_TAG=beta-win64-YYYY-MM-DD (matching the existing
  /// tag convention). Empty by default, meaning update-checking is inert
  /// until a real value is supplied at build time - same pattern as
  /// ANTHROPIC_API_KEY only being "configured" when actually set.
  static const _currentTag = String.fromEnvironment('BUILD_TAG');

  Future<AvailableUpdate?> checkForUpdate() async {
    if (_currentTag.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latestTag = json['tag_name'] as String?;
      final htmlUrl = json['html_url'] as String?;
      if (latestTag == null || htmlUrl == null) return null;
      if (latestTag == _currentTag) return null;

      return AvailableUpdate(
        tag: latestTag,
        htmlUrl: htmlUrl,
        notes: json['body'] as String?,
      );
    } catch (_) {
      // Network error, private-repo 404, malformed response - all treated
      // the same: no update info available right now, not a fatal error.
      return null;
    }
  }
}
