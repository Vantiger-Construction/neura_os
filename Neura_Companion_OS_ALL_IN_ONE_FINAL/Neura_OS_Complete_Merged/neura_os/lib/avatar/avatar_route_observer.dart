import 'package:flutter/material.dart';

import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';

/// Route observer that emits NeuraRouteEvent on navigation changes.
/// Works with named routes *and* falls back to route.runtimeType if unnamed.
class AvatarRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final NeuraEventBus bus;

  AvatarRouteObserver(this.bus);

  String _routeName(Route<dynamic>? route) {
    final settings = route?.settings;
    final name = settings?.name;
    if (name != null && name.trim().isNotEmpty) return name;
    return route?.runtimeType.toString() ?? 'unknown_route';
  }

  void _emit(Route<dynamic>? route) {
    bus.emit(NeuraRouteEvent(_routeName(route)));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _emit(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _emit(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _emit(previousRoute);
  }
}
