import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../neura_avatar_runtime_bridge.dart';
import 'neura_presence_relay_config.dart';

typedef NeuraPresenceRelayConnector = Future<WebSocket> Function(
  Uri endpoint,
  Map<String, dynamic> headers,
);

Future<WebSocket> _defaultConnect(Uri endpoint, Map<String, dynamic> headers) =>
    WebSocket.connect(endpoint.toString(), headers: headers);

/// Publishes Neura's avatar presence to the opt-in `neura_api` relay.
///
/// Starts only when the trusted launcher set both relay variables. It sends
/// the content-free v1 snapshot on every change and every [heartbeat] (the
/// relay withdraws a snapshot that is not refreshed within six seconds), and
/// withdraws it when the app is hidden, paused or detached. Losing the
/// connection simply withdraws presence at the relay; this side reconnects
/// with backoff. No frame content is read from the relay.
class NeuraPresenceRelayPublisher with WidgetsBindingObserver {
  NeuraPresenceRelayPublisher({
    required NeuraPresenceRelayConfig config,
    required ValueListenable<NeuraAvatarRuntimeSnapshot?> source,
    NeuraPresenceRelayConnector connect = _defaultConnect,
    this.heartbeat = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 30),
  })  : _config = config,
        _source = source,
        _connect = connect;

  static NeuraPresenceRelayPublisher? _active;

  /// Starts the app-wide publisher when launched with relay settings.
  /// Idempotent; does nothing in an ordinary launch.
  static void startFromEnvironment() {
    if (_active != null) return;
    final config =
        NeuraPresenceRelayConfig.fromEnvironment(Platform.environment);
    if (config == null) return;
    _active = NeuraPresenceRelayPublisher(
      config: config,
      source: NeuraAvatarRuntimeBridge.instance.snapshot,
    )..start();
  }

  final NeuraPresenceRelayConfig _config;
  final ValueListenable<NeuraAvatarRuntimeSnapshot?> _source;
  final NeuraPresenceRelayConnector _connect;
  final Duration heartbeat;
  final Duration maxBackoff;

  WebSocket? _socket;
  Timer? _heartbeat;
  Timer? _retry;
  bool _running = false;
  bool _foreground = true;
  int _attempt = 0;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  void start() {
    if (_running) return;
    _running = true;
    _source.addListener(_sendCurrent);
    WidgetsBinding.instance.addObserver(this);
    _heartbeat = Timer.periodic(heartbeat, (_) => _sendCurrent());
    unawaited(_open());
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _source.removeListener(_sendCurrent);
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _retry?.cancel();
    final socket = _socket;
    _socket = null;
    if (identical(_active, this)) _active = null;
    if (socket == null) return;
    _send(socket, neuraPresenceClearMessage);
    try {
      await socket.close(WebSocketStatus.normalClosure);
    } catch (_) {
      // The relay withdraws presence when the connection ends either way.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` stays live: on desktop it means another window (such as
    // the Unity presence stage) has focus, not that Neura went away.
    _foreground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _sendCurrent();
  }

  Future<void> _open() async {
    if (!_running) return;
    final headers = <String, dynamic>{
      HttpHeaders.authorizationHeader: _config.authorization,
    };
    try {
      final socket = await _connect(
        _config.endpoint,
        headers,
      ).timeout(const Duration(seconds: 5));
      if (!_running) {
        unawaited(socket.close().catchError((Object _) {}));
        return;
      }
      _socket = socket;
      _attempt = 0;
      socket.listen(
        (_) {},
        onError: (Object _) => _closed(socket),
        onDone: () => _closed(socket),
        cancelOnError: true,
      );
      _sendCurrent();
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _closed(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running || _retry?.isActive == true) return;
    final seconds = min(maxBackoff.inSeconds, 1 << min(_attempt++, 5));
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      unawaited(_open());
    });
  }

  void _sendCurrent() {
    final socket = _socket;
    if (!_running || socket == null) return;
    final snapshot = _source.value;
    _send(
      socket,
      _foreground && snapshot != null
          ? neuraPresencePublishMessage(snapshot)
          : neuraPresenceClearMessage,
    );
  }

  void _send(WebSocket socket, String message) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(message);
    } catch (_) {
      _closed(socket);
    }
  }
}
