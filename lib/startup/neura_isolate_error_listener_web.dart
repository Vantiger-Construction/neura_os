/// Web no-op matching the native root-isolate listener API.
///
/// Flutter's PlatformDispatcher handler remains active on web. A separate
/// `dart:isolate` listener cannot be installed there.
class NeuraIsolateErrorListener {
  NeuraIsolateErrorListener._();

  static NeuraIsolateErrorListener attach(
    void Function(dynamic message) onError,
  ) {
    return NeuraIsolateErrorListener._();
  }

  void close() {}
}
