/// Placeholder/stub for a cross-platform kids-game launcher.
/// In practice, auto-detecting installed games is platform-specific and often restricted,
/// so this service starts as a simple manual list + TODO hooks.
class KidsGameLibraryService {
  KidsGameLibraryService._internal();
  static final KidsGameLibraryService instance =
      KidsGameLibraryService._internal();

  /// For now, a simple map of "game name" -> "launch command / URL".
  /// Parents can configure paths or URLs in a future settings screen.
  final Map<String, String> _entries = {
    'Calm Breathing Game': 'neura://kids/breathing',
    'Gratitude Stars': 'neura://kids/gratitude',
  };

  List<String> get games => _entries.keys.toList();

  String? getLaunchTarget(String name) => _entries[name];

  Future<bool> launchGame(String name) async {
    final target = _entries[name];
    if (target == null) return false;

    // TODO: per-platform integration:
    // - On Android: use MethodChannel to open package name or deep link
    // - On iOS: deep links only
    // - On desktop: Process.start with path, carefully validated
    // For now we just return false for non-internal targets.
    if (target.startsWith('neura://')) {
      // Let the Flutter side route this within your app (mini-games).
      return true;
    }

    // External targets are not implemented yet.
    return false;
  }
}
