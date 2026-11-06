import 'package:flutter/widgets.dart';

/// Synchronous route changes revoke a restore even if the covering route is
/// removed before another frame or the final storage permit check.
class VaultRestoreRouteObserver extends NavigatorObserver {
  final _listeners = <void Function(Route<dynamic>)>{};

  void addListener(void Function(Route<dynamic>) listener) =>
      _listeners.add(listener);
  void removeListener(void Function(Route<dynamic>) listener) =>
      _listeners.remove(listener);

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    for (final listener in _listeners.toList()) {
      listener(topRoute);
    }
  }
}

final vaultRestoreRouteObserver = VaultRestoreRouteObserver();
