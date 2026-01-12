import 'dart:async';

typedef NeuraNavigate = void Function(String route);

/// Routes Unity events to Flutter navigation.
/// Works with:
/// - PROP_ACTIVATED (preferred)
/// - PROP_CLICKED (fallback)
/// - NEURA_ARRIVED (optional hook)
class NeuraEventRouter {
  final Map<String, String> propToRoute;
  final NeuraNavigate navigate;

  StreamSubscription? _sub;

  NeuraEventRouter({
    required this.propToRoute,
    required this.navigate,
  });

  void bind(Stream<Map<String, dynamic>> events) {
    _sub?.cancel();
    _sub = events.listen((e) {
      final type = e['type'];
      if (type != 'EVENT') return;

      final event = e['event']?.toString();
      final value = e['value']?.toString();

      if (value == null || value.isEmpty) return;

      // Prefer activated (after Neura walks there)
      if (event == 'PROP_ACTIVATED' || event == 'PROP_CLICKED') {
        final route = propToRoute[value];
        if (route != null) navigate(route);
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
