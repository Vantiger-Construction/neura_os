import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum SidecarState { stopped, starting, running, crashLoop }

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
  final List<DateTime> _crashes = [];
  Process? _process;
  bool _wanted = false;
  int _attempt = 0;

  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    await _launch();
  }

  Future<void> _launch() async {
    if (!_wanted) return;
    state.add(SidecarState.starting);
    final file = File(executablePath);
    if (!await file.exists()) {
      _wanted = false;
      throw StateError('Sidecar not found: $executablePath');
    }
    try {
      final process = await Process.start(
        executablePath,
        arguments,
        workingDirectory: file.parent.path,
        runInShell: false,
      );
      _process = process;
      state.add(SidecarState.running);
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(logs.add);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => logs.add('[stderr] $line'));
      final code = await process.exitCode;
      if (_wanted && identical(_process, process)) await _crashed(code);
    } catch (error) {
      logs.add('[launch] $error');
      if (_wanted) await _crashed(-1);
    }
  }

  Future<void> _crashed(int code) async {
    final now = DateTime.now();
    _crashes.add(now);
    _crashes.removeWhere((time) => now.difference(time) > crashWindow);
    logs.add('[exit] code=$code');
    if (_crashes.length >= maxCrashes) {
      _wanted = false;
      state.add(SidecarState.crashLoop);
      return;
    }
    final delay = Duration(seconds: 1 << min(_attempt++, 5));
    await Future<void>.delayed(delay);
    await _launch();
  }

  Future<void> stop() async {
    _wanted = false;
    _process?.kill();
    _process = null;
    _attempt = 0;
    state.add(SidecarState.stopped);
  }

  Future<void> dispose() async {
    await stop();
    await state.close();
    await logs.close();
  }
}
