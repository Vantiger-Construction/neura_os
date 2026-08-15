import 'dart:async';

import 'envelope.dart';

enum BrainConnectionState { stopped, connecting, connected, reconnecting }

/// Web-safe fallback for the local native brain connection.
///
/// Browsers cannot launch Neura's local sidecar process. The console remains
/// loadable and clearly reports that limitation instead of breaking the web
/// build at compile time.
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

  Stream<Envelope> get events => _events.stream;
  Stream<BrainConnectionState> get states => _states.stream;
  bool get isConnected => false;

  void start() => _states.add(BrainConnectionState.stopped);

  bool send(String kind, Map<String, dynamic> data, {String? id}) => false;

  String sendUserText(String text) {
    throw UnsupportedError(
      'Neura Local Brain is available in Windows and mobile builds.',
    );
  }

  void enterRoom(String room) {}
  void requestDiagnostics() {}

  Future<void> dispose() async {
    await _events.close();
    await _states.close();
  }
}
