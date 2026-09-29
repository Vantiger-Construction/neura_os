import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'neura_chat_policy.dart';

class NeuraApiProposal {
  NeuraApiProposal(
    this.id,
    this.requestId,
    this.action,
    this.arguments,
    this.createdAt,
  );

  final String id;
  final String requestId;
  final String action;
  final Map<String, dynamic> arguments;
  final DateTime createdAt;
  String status = 'pending';
  DateTime? finalizedAt;

  Map<String, Object> get receipt => {'id': id, 'status': status};
}

class _NeuraRequestRecord {
  const _NeuraRequestRecord(this.fingerprint, this.proposalId);

  final String fingerprint;
  final String proposalId;
}

/// Session-only, loopback-only API. Remote callers can propose, never approve.
class NeuraLocalApi {
  NeuraLocalApi({
    required this.allowed,
    this.onChanged,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const apiVersion = 1;
  static const apiMinorVersion = 1;
  static const lifetime = Duration(minutes: 2);
  static const receiptRetention = Duration(minutes: 10);
  static const maxBodyBytes = 4096;
  static const maxRequestsPerMinute = 60;
  static const maxInFlight = 8;
  static const maxActiveProposals = 16;
  static const maxReceipts = 64;
  static const maxSessionRequestIds = 256;
  static const _versionHeader = 'x-neura-api-version';
  static const _traceHeader = 'x-neura-trace-id';

  final bool Function() allowed;
  final void Function()? onChanged;
  final DateTime Function() _now;
  HttpServer? _server;
  String? _token;
  final _proposals = <String, NeuraApiProposal>{};
  final _requestIds = <String, _NeuraRequestRecord>{};
  DateTime? _window;
  int _requests = 0;
  int _inFlight = 0;
  int _epoch = 0;
  bool _starting = false;

  bool get running => _server != null;
  String? get token => _token;
  int? get port => _server?.port;

  List<NeuraApiProposal> get pending {
    _maintainReceipts();
    return _proposals.values
        .where((proposal) => proposal.status == 'pending')
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
      server.listen(
        (request) => unawaited(_handle(request)),
        onError: (_) => unawaited(stop()),
      );
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
    _requestIds.clear();
    _requests = 0;
    _window = null;
    onChanged?.call();
    await server?.close(force: true);
  }

  /// Only the visible native UI may call this, after showing exact arguments.
  NeuraApiProposal? takeForApproval(String id) {
    _maintainReceipts();
    final proposal = _proposals[id];
    if (!running || !allowed() || proposal?.status != 'pending') return null;
    proposal!.status = 'reviewing';
    onChanged?.call();
    return proposal;
  }

  bool canApply(NeuraApiProposal proposal) {
    _maintainReceipts();
    return running &&
        allowed() &&
        identical(_proposals[proposal.id], proposal) &&
        proposal.status == 'reviewing' &&
        _now().difference(proposal.createdAt) < lifetime;
  }

  void finish(NeuraApiProposal proposal, String status) {
    if (identical(_proposals[proposal.id], proposal)) {
      proposal.status = status;
      proposal.finalizedAt = _now();
      _maintainReceipts();
      onChanged?.call();
    }
  }

  void _maintainReceipts() {
    final now = _now();
    for (final proposal in _proposals.values) {
      if ((proposal.status == 'pending' || proposal.status == 'reviewing') &&
          now.difference(proposal.createdAt) >= lifetime) {
        proposal.status = 'expired';
        proposal.finalizedAt = now;
      }
    }
    final staleIds = _proposals.values
        .where((proposal) =>
            proposal.finalizedAt != null &&
            now.difference(proposal.finalizedAt!) >= receiptRetention)
        .map((proposal) => proposal.id)
        .toList(growable: false);
    for (final id in staleIds) {
      _proposals.remove(id);
    }
  }

  void _makeReceiptRoom() {
    _maintainReceipts();
    if (_proposals.length < maxReceipts) return;
    final finalized = _proposals.values
        .where((proposal) => proposal.finalizedAt != null)
        .toList()
      ..sort((a, b) => a.finalizedAt!.compareTo(b.finalizedAt!));
    for (final proposal in finalized) {
      _proposals.remove(proposal.id);
      if (_proposals.length < maxReceipts) return;
    }
  }

  int get _activeProposalCount => _proposals.values
      .where((proposal) =>
          proposal.status == 'pending' || proposal.status == 'reviewing')
      .length;

  static String _randomId() =>
      base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');

  bool _authenticated(HttpRequest request) {
    final expected = 'Bearer ${_token ?? ''}';
    final actual = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    var difference = actual.length ^ expected.length;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^
          (index < actual.length ? actual.codeUnitAt(index) : 0);
    }
    return _token != null && difference == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final epoch = _epoch;
    final traceId = _randomId().substring(0, 16);
    _inFlight++;
    try {
      if (!running || !allowed()) {
        return await _error(request, 503, 'unavailable', traceId);
      }
      if (_inFlight > maxInFlight) {
        return await _error(
          request,
          429,
          'busy',
          traceId,
          retryAfterSeconds: 1,
        );
      }
      // This API is for native local clients, never browser-origin requests.
      if (request.headers.value('origin') != null || !_authenticated(request)) {
        return await _error(request, 401, 'unauthorized', traceId);
      }
      final requestedVersion = request.headers.value(_versionHeader);
      if (requestedVersion != null && requestedVersion != '$apiVersion') {
        return await _error(request, 426, 'unsupported_api_version', traceId);
      }

      final now = _now();
      if (_window == null ||
          now.difference(_window!) >= const Duration(minutes: 1)) {
        _window = now;
        _requests = 0;
      }
      if (++_requests > maxRequestsPerMinute) {
        final remaining = const Duration(minutes: 1) - now.difference(_window!);
        return await _error(
          request,
          429,
          'rate_limited',
          traceId,
          retryAfterSeconds: max(1, remaining.inSeconds),
        );
      }

      _maintainReceipts();
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        return await _reply(
            request,
            200,
            {
              'api_version': apiVersion,
              'api_minor_version': apiMinorVersion,
              'contract_version': '$apiVersion.$apiMinorVersion',
              'status': 'ready',
              'approval_required': true,
            },
            traceId);
      }
      if (request.method == 'GET' && path == '/v1/capabilities') {
        return await _reply(request, 200, _capabilities(), traceId);
      }
      if (request.method == 'GET' && path.startsWith('/v1/proposals/')) {
        final proposal = _proposals[path.substring('/v1/proposals/'.length)];
        if (proposal == null) {
          return await _error(request, 404, 'not_found', traceId);
        }
        return await _reply(request, 200, proposal.receipt, traceId);
      }
      if (request.method != 'POST' || path != '/v1/proposals') {
        return await _error(request, 404, 'not_found', traceId);
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        return await _error(request, 415, 'json_required', traceId);
      }
      if (request.contentLength > maxBodyBytes) {
        return await _error(request, 413, 'too_large', traceId);
      }

      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 5))) {
        if (bytes.length + chunk.length > maxBodyBytes) {
          return await _error(request, 413, 'too_large', traceId);
        }
        bytes.addAll(chunk);
      }
      if (!allowed() || !running || epoch != _epoch) {
        return await _error(request, 503, 'unavailable', traceId);
      }

      final body = jsonDecode(utf8.decode(bytes));
      if (body is! Map<String, dynamic> ||
          body.keys.any(
            (key) => !{'request_id', 'action', 'arguments'}.contains(key),
          )) {
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
      if (!_validAction(action, arguments)) {
        return await _error(request, 400, 'invalid_action', traceId);
      }

      final fingerprint = '$action:${_canonicalJson(arguments)}';
      final previous = _requestIds[requestId];
      if (previous != null) {
        if (previous.fingerprint != fingerprint) {
          return await _error(request, 409, 'request_id_reused', traceId);
        }
        final proposal = _proposals[previous.proposalId];
        if (proposal == null) {
          return await _error(request, 410, 'request_id_retired', traceId);
        }
        return await _reply(request, 200, proposal.receipt, traceId);
      }
      if (_requestIds.length >= maxSessionRequestIds) {
        return await _error(request, 429, 'session_request_limit', traceId);
      }
      if (_activeProposalCount >= maxActiveProposals) {
        return await _error(
          request,
          429,
          'active_proposal_limit',
          traceId,
          retryAfterSeconds: 1,
        );
      }
      _makeReceiptRoom();
      if (_proposals.length >= maxReceipts) {
        return await _error(
          request,
          429,
          'receipt_capacity',
          traceId,
          retryAfterSeconds: 1,
        );
      }

      final proposal = NeuraApiProposal(
        _randomId(),
        requestId,
        action,
        Map.unmodifiable(arguments),
        now,
      );
      _proposals[proposal.id] = proposal;
      _requestIds[requestId] = _NeuraRequestRecord(fingerprint, proposal.id);
      onChanged?.call();
      return await _reply(request, 202, proposal.receipt, traceId);
    } on TimeoutException {
      await _error(request, 408, 'request_timeout', traceId);
    } catch (_) {
      try {
        await _error(request, 400, 'invalid_request', traceId);
      } catch (_) {}
    } finally {
      _inFlight--;
    }
  }

  Map<String, Object?> _capabilities() {
    final rooms = NeuraChatPolicy.knownRoomIds.toList()..sort();
    final tones = NeuraChatPolicy.knownTones.toList()..sort();
    return {
      'api_version': apiVersion,
      'api_minor_version': apiMinorVersion,
      // Kept for v1 client compatibility.
      'actions': ['open_room', 'set_tone', 'sync_journal'],
      'action_contracts': {
        'open_room': {
          'argument_name': 'room',
          'value_required': true,
          'allowed_values': rooms,
        },
        'set_tone': {
          'argument_name': 'tone',
          'value_required': true,
          'allowed_values': tones,
        },
        'sync_journal': {
          'argument_name': null,
          'value_required': false,
          'allowed_values': <String>[],
        },
      },
      'limits': {
        'body_bytes': maxBodyBytes,
        'requests_per_minute': maxRequestsPerMinute,
        'in_flight': maxInFlight,
        'active_proposals': maxActiveProposals,
        'receipts': maxReceipts,
        'session_request_ids': maxSessionRequestIds,
        'proposal_lifetime_seconds': lifetime.inSeconds,
        'receipt_retention_seconds': receiptRetention.inSeconds,
      },
      'approval': 'each_action_in_neura',
      'cloud_ai': false,
      'memory_access': false,
    };
  }

  bool _validAction(String action, Map<String, dynamic> arguments) {
    return switch (action) {
      'open_room' => arguments.length == 1 &&
          NeuraChatPolicy.knownRoomIds.contains(arguments['room']),
      'set_tone' => arguments.length == 1 &&
          NeuraChatPolicy.knownTones.contains(arguments['tone']),
      'sync_journal' => arguments.isEmpty,
      _ => false,
    };
  }

  String _canonicalJson(Object? value) {
    Object? canonicalize(Object? item) {
      if (item is Map) {
        final keys = item.keys.map((key) => key.toString()).toList()..sort();
        return {
          for (final key in keys) key: canonicalize(item[key]),
        };
      }
      if (item is List) return item.map(canonicalize).toList();
      return item;
    }

    return jsonEncode(canonicalize(value));
  }

  Future<void> _error(
    HttpRequest request,
    int status,
    String code,
    String traceId, {
    int? retryAfterSeconds,
  }) {
    final retryable = const {
      'unavailable',
      'busy',
      'rate_limited',
      'request_timeout',
      'active_proposal_limit',
      'receipt_capacity',
    }.contains(code);
    return _reply(
      request,
      status,
      {
        // The string field remains stable for existing v1 clients.
        'error': code,
        'error_info': {
          'code': code,
          'retryable': retryable,
          'trace_id': traceId,
        },
      },
      traceId,
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
    String traceId, {
    int? retryAfterSeconds,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('cache-control', 'no-store');
    request.response.headers.set('x-content-type-options', 'nosniff');
    request.response.headers.set(_versionHeader, '$apiVersion');
    request.response.headers.set(_traceHeader, traceId);
    if (retryAfterSeconds != null) {
      request.response.headers.set('retry-after', '$retryAfterSeconds');
    }
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
