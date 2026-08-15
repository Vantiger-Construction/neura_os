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
  int _attempt = 0;
  String? _lastRoom;

  Stream<Envelope> get events => _events.stream;
  Stream<BrainConnectionState> get states => _states.stream;
  bool get isConnected => _socket?.readyState == WebSocket.open;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> _connect() async {
    if (!_running) return;
    _states.add(
      _attempt == 0
          ? BrainConnectionState.connecting
          : BrainConnectionState.reconnecting,
    );
    try {
      final socket = await WebSocket.connect(
        url,
      ).timeout(const Duration(seconds: 8));
      if (!_running) {
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
    if (_running) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running || _retry?.isActive == true) return;
    _states.add(BrainConnectionState.reconnecting);
    final seconds = min(maxBackoff.inSeconds, 1 << min(_attempt++, 5));
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  bool send(String kind, Map<String, dynamic> data, {String? id}) {
    if (!isConnected) return false;
    _socket!.add(
      Envelope(kind: kind, id: id ?? _newId(), data: data).encode(),
    );
    return true;
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
    _running = false;
    _retry?.cancel();
    await _socket?.close(WebSocketStatus.normalClosure, 'client shutdown');
    await _events.close();
    await _states.close();
  }
}
