import 'dart:async';
import 'dart:convert';
import 'dart:io';

class NeuraWindowsBridge {
  final String unityExePath;
  final int port;

  Process? _proc;
  Socket? _sock;
  StreamSubscription<String>? _sockSub;

  final List<void Function(Map<String, dynamic>)> _listeners = [];

  NeuraWindowsBridge({required this.unityExePath, this.port = 49152});

  void onEvent(void Function(Map<String, dynamic>) cb) => _listeners.add(cb);

  Future<void> start() async {
    // Launch Unity EXE (detached). Use your packaged path.
    _proc ??= await Process.start(
      unityExePath,
      [],
      mode: ProcessStartMode.detachedWithStdio,
    );

    // Retry connect while Unity boots
    for (var i = 0; i < 40; i++) {
      try {
        _sock = await Socket.connect(InternetAddress.loopbackIPv4, port,
            timeout: const Duration(milliseconds: 250));
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    if (_sock == null) {
      throw Exception("Couldn't connect to Unity on 127.0.0.1:$port");
    }

    _sockSub = _sock!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        for (final cb in _listeners) {
          cb(msg);
        }
      } catch (_) {
        // ignore junk lines
      }
    });
  }

  void send(Map<String, dynamic> msg) {
    final line = jsonEncode(msg);
    _sock?.write('$line\n');
  }

  Future<void> stop() async {
    await _sockSub?.cancel();
    _sockSub = null;
    await _sock?.close();
    _sock = null;
    // Unity stays running if detached; you can add a QUIT action later.
    _proc = null;
  }
}
