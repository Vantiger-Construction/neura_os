import 'dart:async';
import 'package:flutter/foundation.dart';
import 'brain_link.dart';
import 'diagnostics.dart';
import 'envelope.dart';
import 'neura_tone.dart';

enum ConversationRole { user, neura }

class ConversationMessage {
  const ConversationMessage(
      {required this.id,
      required this.role,
      required this.text,
      this.streaming = false,
      this.interrupted = false});
  final String id;
  final ConversationRole role;
  final String text;
  final bool streaming;
  final bool interrupted;
  ConversationMessage copyWith(
          {String? text, bool? streaming, bool? interrupted}) =>
      ConversationMessage(
          id: id,
          role: role,
          text: text ?? this.text,
          streaming: streaming ?? this.streaming,
          interrupted: interrupted ?? this.interrupted);
}

class ConversationController extends ChangeNotifier {
  ConversationController({required this.link, this.onDispatchIntent}) {
    _subscription = link.events.listen(_onEnvelope);
    _stateSubscription = link.states.listen((_) => notifyListeners());
  }
  final BrainLink link;
  final ValueChanged<Map<String, dynamic>>? onDispatchIntent;
  final ToneController tone = ToneController();
  final List<ConversationMessage> _messages = [];
  StreamSubscription<Envelope>? _subscription;
  StreamSubscription<BrainConnectionState>? _stateSubscription;
  DiagnosticsSnapshot? diagnostics;
  List<ConversationMessage> get messages => List.unmodifiable(_messages);

  String send(String text) {
    final clean = text.trim();
    if (clean.isEmpty)
      throw ArgumentError.value(text, 'text', 'must not be empty');
    final id = link.sendUserText(clean);
    _messages.add(
        ConversationMessage(id: id, role: ConversationRole.user, text: clean));
    notifyListeners();
    return id;
  }

  void enterRoom(String room) => link.enterRoom(room);
  void requestDiagnostics() => link.requestDiagnostics();

  void _onEnvelope(Envelope envelope) {
    final data = envelope.data;
    switch (envelope.kind) {
      case 'speak_delta':
        final id = data['utterance_id'] as String? ?? envelope.id;
        final delta = data['delta'] as String? ?? data['text'] as String? ?? '';
        _upsert(id, delta: delta, streaming: true);
      case 'speak':
        final id = data['utterance_id'] as String? ?? envelope.id;
        final text = data['text'] as String?;
        _upsert(id, replacement: text, streaming: false);
      case 'speak_interrupted':
        final id = data['utterance_id'] as String? ?? envelope.id;
        _upsert(id, streaming: false, interrupted: true);
      case 'set_tone':
        tone.setFromWire(data['tone'] as String?);
      case 'dispatch_intent':
        onDispatchIntent?.call(data);
      case 'diagnostics':
        diagnostics = DiagnosticsSnapshot.fromJson(data);
    }
    notifyListeners();
  }

  void _upsert(String id,
      {String? delta,
      String? replacement,
      required bool streaming,
      bool interrupted = false}) {
    final index = _messages.indexWhere((message) =>
        message.id == id && message.role == ConversationRole.neura);
    if (index < 0) {
      _messages.add(ConversationMessage(
          id: id,
          role: ConversationRole.neura,
          text: replacement ?? delta ?? '',
          streaming: streaming,
          interrupted: interrupted));
    } else {
      final old = _messages[index];
      _messages[index] = old.copyWith(
          text: replacement ?? '${old.text}${delta ?? ''}',
          streaming: streaming,
          interrupted: interrupted);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stateSubscription?.cancel();
    tone.dispose();
    super.dispose();
  }
}
