import 'package:flutter/material.dart';
import 'local_profile_service.dart';
import 'local_profile_workspace.dart';

/// Removes the legacy Navigator, including covered routes and their caches.
/// A separate Navigator owns only the profile workspace and its style editor.
class LocalProfileGate extends StatelessWidget {
  const LocalProfileGate({super.key, required this.child});
  final Widget child;
  static final _navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: LocalProfileService.instance,
      builder: (context, _) => LocalProfileService.instance.enabled
          ? Navigator(
              key: _navigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const LocalProfileWorkspace()))
          : child);
}
