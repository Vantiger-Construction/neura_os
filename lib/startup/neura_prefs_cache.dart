import 'package:shared_preferences/shared_preferences.dart';

/// Caches the [SharedPreferences] instance so every service in the app
/// shares the same object without redundant async [getInstance] calls.
///
/// Call [NeuraPrefsCache.init] once in [NeuraStartupCoordinator.boot]
/// before any service reads prefs.  After that, use [NeuraPrefsCache.prefs]
/// synchronously anywhere.

class NeuraPrefsCache {
  NeuraPrefsCache._();

  static SharedPreferences? _instance;
  static Future<void>? _initFuture;

  /// Loads and caches the [SharedPreferences] singleton.
  /// Safe to call concurrently from multiple call sites; all callers await
  /// the same underlying load. A failed attempt is not cached permanently,
  /// so a later startup/shell retry can recover from a transient plugin error.
  static Future<void> init() {
    final existing = _initFuture;
    if (existing != null) return existing;
    late final Future<void> attempt;
    attempt = Future<SharedPreferences>.sync(
      SharedPreferences.getInstance,
    ).then<void>((prefs) {
      _instance = prefs;
    }).onError((Object error, StackTrace stackTrace) {
      if (identical(_initFuture, attempt)) _initFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _initFuture = attempt;
    return attempt;
  }

  /// The cached [SharedPreferences] instance.
  /// Throws [StateError] if [init] has not completed yet.
  static SharedPreferences get prefs {
    final p = _instance;
    if (p == null) {
      throw StateError(
        'NeuraPrefsCache.prefs accessed before NeuraPrefsCache.init().',
      );
    }
    return p;
  }

  /// Returns the cached instance, or null if not yet initialised.
  static SharedPreferences? get prefsOrNull => _instance;
}
