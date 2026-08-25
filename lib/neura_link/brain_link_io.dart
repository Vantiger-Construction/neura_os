import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'envelope.dart';

enum BrainConnectionState { stopped, connecting, connected, reconnecting }

class BrainLink {
  BrainLink({
    required this.url,
    this.clientName = 'neura_os',
    this.maxBackoff = const Duration(seconds: 30),
  });

  final String url;
  final String clientName;
  final Duration maxBackoff;
  final _events = StreamController<Envelope>.broadcast();
  final _states = StreamController<BrainConnectionState>.broadcast();
  WebSocket? _socket;
  Timer? _retry;
  bool _running = false;
  bool _disposed = false;
  int _attempt = 0;
  String? _lastRoom;

  Stream<Envelope> get events => _events.stream;
  Stream<BrainConnectionState> get states => _states.stream;
  bool get isConnected => _socket?.readyState == WebSocket.open;

  void start() {
    if (_disposed) {
      throw StateError('A disposed Neura brain link cannot be restarted.');
    }
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running || _disposed) return;
    _states.add(
      _attempt == 0
          ? BrainConnectionState.connecting
          : BrainConnectionState.reconnecting,
    );
    try {
      final socket = await WebSocket.connect(
        url,
      ).timeout(const Duration(seconds: 8));
      if (!_running || _disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _attempt = 0;
      _states.add(BrainConnectionState.connected);
      send('hello', {'client': clientName, 'protocol_version': 1});
      if (_lastRoom != null) send('room_entered', {'room': _lastRoom});
      socket.listen(
        _receive,
        onError: (_) => _disconnected(socket),
        onDone: () => _disconnected(socket),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _receive(dynamic frame) {
    if (_disposed) return;
    try {
      final decoded = jsonDecode(
        frame is String ? frame : String.fromCharCodes(frame as List<int>),
      );
      if (decoded is Map<String, dynamic>) {
        _events.add(Envelope.fromJson(decoded));
      }
    } catch (error, stack) {
      _events.addError(
        FormatException('Invalid Neura envelope: $error'),
        stack,
      );
    }
  }

  void _disconnected(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    if (_running && !_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running || _disposed || _retry?.isActive == true) return;
    _states.add(BrainConnectionState.reconnecting);
    final seconds = min(maxBackoff.inSeconds, 1 << min(_attempt++, 5));
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      unawaited(_connect());
    });
  }

  bool send(String kind, Map<String, dynamic> data, {String? id}) {
    final socket = _socket;
    if (_disposed || socket == null || socket.readyState != WebSocket.open) {
      return false;
    }
    try {
      socket.add(Envelope(kind: kind, id: id ?? _newId(), data: data).encode());
      return true;
    } catch (_) {
      _disconnected(socket);
      return false;
    }
  }

  String sendUserText(String text) {
    final id = _newId();
    if (!send('user_text', {'text': text, 'utterance_id': id}, id: id)) {
      throw StateError('Neura brain is not connected');
    }
    return id;
  }

  void enterRoom(String room) {
    _lastRoom = room;
    send('room_entered', {'room': room});
  }

  void requestDiagnostics() => send('diagnostics_request', const {});

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _retry?.cancel();
    _retry = null;
    final socket = _socket;
    _socket = null;
    if (!_states.isClosed) _states.add(BrainConnectionState.stopped);
    try {
      await socket?.close(WebSocketStatus.normalClosure, 'client shutdown');
    } finally {
      await _events.close();
      await _states.close();
    }
  }
}
