import 'package:flutter/material.dart';
import 'neura_event_router.dart';
import 'neura_prop_routes.dart';

/// Wrap your MaterialApp with this and provide an event stream + navigatorKey.
/// Example:
/// MaterialApp(
///   navigatorKey: navKey,
///   builder: (context, child) => NeuraUnityEventBinder(
///     navigatorKey: navKey,
///     events: bridge.events,
///     child: child!,
///   ),
/// )
class NeuraUnityEventBinder extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Stream<Map<String, dynamic>> events;
  final Widget child;

  const NeuraUnityEventBinder({
    super.key,
    required this.navigatorKey,
    required this.events,
    required this.child,
  });

  @override
  State<NeuraUnityEventBinder> createState() => _NeuraUnityEventBinderState();
}

class _NeuraUnityEventBinderState extends State<NeuraUnityEventBinder> {
  late final NeuraEventRouter _router;

  @override
  void initState() {
    super.initState();
    _router = NeuraEventRouter(
      propToRoute: defaultNeuraPropRoutes,
      navigate: (route) => widget.navigatorKey.currentState?.pushNamed(route),
    );
    _router.bind(widget.events);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
