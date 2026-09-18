import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'neura_chat_policy.dart';

class NeuraApiProposal {
  NeuraApiProposal(
      this.id, this.requestId, this.action, this.arguments, this.createdAt);
  final String id;
  final String requestId;
  final String action;
  final Map<String, dynamic> arguments;
  final DateTime createdAt;
  String status = 'pending';
  Map<String, Object> get receipt => {'id': id, 'status': status};
}

/// Session-only, loopback-only API. Remote callers can propose, never approve.
class NeuraLocalApi {
  NeuraLocalApi(
      {required this.allowed, this.onChanged, DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final bool Function() allowed;
  final void Function()? onChanged;
  final DateTime Function() _now;
  HttpServer? _server;
  String? _token;
  final _proposals = <String, NeuraApiProposal>{};
  DateTime? _window;
  int _requests = 0;
  int _inFlight = 0;
  int _epoch = 0;
  bool _starting = false;
  static const lifetime = Duration(minutes: 2);
  bool get running => _server != null;
  String? get token => _token;
  int? get port => _server?.port;
  List<NeuraApiProposal> get pending {
    _expire();
    return _proposals.values
        .where((p) => p.status == 'pending')
        .toList(growable: false);
  }

  Future<void> start() async {
    if (running || _starting) return;
    if (!allowed()) {
      throw StateError('The local API is unavailable in this mode.');
    }
    _starting = true;
    final epoch = _epoch;
    try {
      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
      if (!allowed() || epoch != _epoch) {
        await server.close(force: true);
        return;
      }
      _token = _randomId();
      _server = server;
      server.listen((request) => unawaited(_handle(request)),
          onError: (_) => unawaited(stop()));
      onChanged?.call();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _epoch++;
    final server = _server;
    _server = null;
    _token = null;
    _proposals.clear();
    _requests = 0;
    _window = null;
    onChanged?.call();
    await server?.close(force: true);
  }

  /// Only the visible native UI may call this, after showing exact arguments.
  NeuraApiProposal? takeForApproval(String id) {
    _expire();
    final proposal = _proposals[id];
    if (!running || !allowed() || proposal?.status != 'pending') return null;
    proposal!.status = 'reviewing';
    onChanged?.call();
    return proposal;
  }

  bool canApply(NeuraApiProposal proposal) =>
      running &&
      allowed() &&
      identical(_proposals[proposal.id], proposal) &&
      proposal.status == 'reviewing' &&
      _now().difference(proposal.createdAt) < lifetime;

  void finish(NeuraApiProposal proposal, String status) {
    if (identical(_proposals[proposal.id], proposal)) {
      proposal.status = status;
      onChanged?.call();
    }
  }

  void _expire() {
    for (final proposal in _proposals.values) {
      if ((proposal.status == 'pending' || proposal.status == 'reviewing') &&
          _now().difference(proposal.createdAt) >= lifetime) {
        proposal.status = 'expired';
      }
    }
  }

  static String _randomId() =>
      base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');

  bool _authenticated(HttpRequest request) {
    final expected = 'Bearer ${_token ?? ''}';
    final actual = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^
          (i < actual.length ? actual.codeUnitAt(i) : 0);
    }
    return _token != null && difference == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final epoch = _epoch;
    _inFlight++;
    try {
      if (!running || !allowed()) {
        return _reply(request, 503, {'error': 'unavailable'});
      }
      if (_inFlight > 8) return _reply(request, 429, {'error': 'busy'});
      // This API is for native local clients, never browser-origin requests.
      if (request.headers.value('origin') != null || !_authenticated(request)) {
        return _reply(request, 401, {'error': 'unauthorized'});
      }
      final now = _now();
      if (_window == null ||
          now.difference(_window!) >= const Duration(minutes: 1)) {
        _window = now;
        _requests = 0;
      }
      if (++_requests > 60) {
        return _reply(request, 429, {'error': 'rate_limited'});
      }
      _expire();
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        return _reply(request, 200,
            {'api_version': 1, 'status': 'ready', 'approval_required': true});
      }
      if (request.method == 'GET' && path == '/v1/capabilities') {
        return _reply(request, 200, {
          'actions': ['open_room', 'set_tone', 'sync_journal'],
          'approval': 'each_action_in_neura',
          'cloud_ai': false,
          'memory_access': false
        });
      }
      if (request.method == 'GET' && path.startsWith('/v1/proposals/')) {
        final proposal = _proposals[path.substring('/v1/proposals/'.length)];
        return _reply(request, proposal == null ? 404 : 200,
            proposal?.receipt ?? {'error': 'not_found'});
      }
      if (request.method != 'POST' || path != '/v1/proposals') {
        return _reply(request, 404, {'error': 'not_found'});
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        return _reply(request, 415, {'error': 'json_required'});
      }
      const maxBody = 4096;
      if (request.contentLength > maxBody) {
        return _reply(request, 413, {'error': 'too_large'});
      }
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 5))) {
        if (bytes.length + chunk.length > maxBody) {
          return _reply(request, 413, {'error': 'too_large'});
        }
        bytes.addAll(chunk);
      }
      if (!allowed() || !running || epoch != _epoch) {
        return _reply(request, 503, {'error': 'unavailable'});
      }
      final body = jsonDecode(utf8.decode(bytes));
      if (body is! Map<String, dynamic> ||
          body.keys
              .any((k) => !{'request_id', 'action', 'arguments'}.contains(k))) {
        throw const FormatException();
      }
      final requestId = body['request_id'];
      final action = body['action'];
      final arguments = body['arguments'];
      if (requestId is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(requestId) ||
          action is! String ||
          arguments is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final valid = switch (action) {
        'open_room' => arguments.length == 1 &&
            NeuraChatPolicy.knownRoomIds.contains(arguments['room']),
        'set_tone' => arguments.length == 1 &&
            NeuraChatPolicy.knownTones.contains(arguments['tone']),
        'sync_journal' => arguments.isEmpty,
        _ => false,
      };
      if (!valid) return _reply(request, 400, {'error': 'invalid_action'});
      for (final previous in _proposals.values) {
        if (previous.requestId == requestId) {
          if (previous.action != action ||
              jsonEncode(previous.arguments) != jsonEncode(arguments)) {
            return _reply(request, 409, {'error': 'request_id_reused'});
          }
          return _reply(request, 200, previous.receipt);
        }
      }
      if (_proposals.length >= 64) {
        return _reply(
            request, 429, {'error': 'session_limit_restart_to_clear'});
      }
      final proposal = NeuraApiProposal(
          _randomId(), requestId, action, Map.unmodifiable(arguments), now);
      _proposals[proposal.id] = proposal;
      onChanged?.call();
      return _reply(request, 202, proposal.receipt);
    } on TimeoutException {
      await _reply(request, 408, {'error': 'request_timeout'});
    } catch (_) {
      try {
        await _reply(request, 400, {'error': 'invalid_request'});
      } catch (_) {}
    } finally {
      _inFlight--;
    }
  }

  Future<void> _reply(
      HttpRequest request, int status, Map<String, Object> body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('cache-control', 'no-store');
    request.response.headers.set('x-content-type-options', 'nosniff');
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
