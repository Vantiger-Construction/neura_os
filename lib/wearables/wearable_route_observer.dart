import 'package:flutter/widgets.dart';

class WearableRouteObserver extends NavigatorObserver {
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

final wearableRouteObserver = WearableRouteObserver();
