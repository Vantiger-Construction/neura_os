import 'dart:async';

enum SidecarState { stopped, starting, running, crashLoop }

/// Web-safe fallback. Browsers cannot launch local executable sidecars.
class SidecarManager {
  SidecarManager({
    required this.executablePath,
    this.arguments = const [],
    this.maxCrashes = 5,
    this.crashWindow = const Duration(minutes: 2),
  });

  final String executablePath;
  final List<String> arguments;
  final int maxCrashes;
  final Duration crashWindow;
  final state = StreamController<SidecarState>.broadcast();
  final logs = StreamController<String>.broadcast();

  Future<void> start() async {
    logs.add('Local sidecars are unavailable in browser builds.');
    state.add(SidecarState.stopped);
  }

  Future<void> stop() async => state.add(SidecarState.stopped);

  Future<void> dispose() async {
    await state.close();
    await logs.close();
  }
}
