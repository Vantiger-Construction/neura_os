import 'dart:isolate';

/// Native root-isolate error listener used by Neura's error pipeline.
///
/// Kept outside the platform-neutral pipeline because `dart:isolate` is not
/// available to Flutter web builds.
class NeuraIsolateErrorListener {
  final RawReceivePort _port;
  bool _closed = false;

  NeuraIsolateErrorListener._(this._port);

  static NeuraIsolateErrorListener attach(
    void Function(dynamic message) onError,
  ) {
    final port = RawReceivePort(onError);
    try {
      Isolate.current.addErrorListener(port.sendPort);
      return NeuraIsolateErrorListener._(port);
    } catch (_) {
      port.close();
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      Isolate.current.removeErrorListener(_port.sendPort);
    } finally {
      _port.close();
    }
  }
}
