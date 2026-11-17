import 'package:flutter/widgets.dart';

/// Revoke an in-progress review synchronously, including cover/pop within one
/// frame. The workflow's own review is the only permitted covering route.
class ClinicContactRouteObserver extends NavigatorObserver {
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

final clinicContactRouteObserver = ClinicContactRouteObserver();
