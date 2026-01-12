import 'package:flutter/material.dart';

import '../avatar/avatar_globals.dart';
import '../avatar/avatar_host.dart';
import '../avatar/avatar_route_observer.dart';
import '../core/neura_event_bus.dart';
import '../integrations/neura_sources_hooks.dart';
import '../screens/home_screen.dart';

class NeuraApp extends StatelessWidget {
  const NeuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neura Companion',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [AvatarRouteObserver(NeuraEventBus.I)],
      builder: (context, child) {
        final c = child ?? const SizedBox.shrink();
        return GlobalAvatarHost(
          child: c,
          controller: AvatarGlobals.controller,
          avatarService: AvatarGlobals.service,
          onTap: () {
            // A tiny default interaction: wave when the user taps Neura.
            NeuraSourcesHooks.pulseWave();
          },
        );
      },
      home: const HomeScreen(),
    );
  }
}

