import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_local_api.dart';

void main() {
  late NeuraLocalApi api;
  late HttpClient client;
  var allowed = true;
  var now = DateTime.utc(2026, 9, 18);
  Future<(int, Map<String, dynamic>, HttpHeaders)> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    bool browser = false,
    String? apiVersion = '1',
  }) async {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${api.port}$path'));
    if (authenticated) req.headers.set('authorization', 'Bearer ${api.token}');
    if (browser) req.headers.set('origin', 'https://example.com');
    if (apiVersion != null) {
      req.headers.set('x-neura-api-version', apiVersion);
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    final decoded = jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
    return (response.statusCode, decoded, response.headers);
  }

  setUp(() async {
    allowed = true;
    now = DateTime.utc(2026, 9, 18);
    api = NeuraLocalApi(allowed: () => allowed, now: () => now);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
    await api.start();
  });
  tearDown(() async {
    client.close(force: true);
    await api.stop();
  });

  test('every route needs authentication and rejects browser origins',
      () async {
    expect((await request('GET', '/v1/health', authenticated: false)).$1, 401);
    expect((await request('GET', '/v1/health', browser: true)).$1, 401);
    final health = await request('GET', '/v1/health');
    expect(health.$1, 200);
    expect(health.$2['approval_required'], true);
    expect(health.$2['api_minor_version'], 1);
    expect(health.$3.value('x-neura-api-version'), '1');
    expect(health.$3.value('x-neura-trace-id'), isNotEmpty);
    expect((await request('POST', '/v1/execute', body: {})).$1, 404);
    expect((await request('GET', '/v1/memory')).$1, 404);
  });
  test('capabilities advertise versioned action contracts and limits',
      () async {
    final response = await request('GET', '/v1/capabilities');
    expect(response.$1, 200);
    expect(response.$2['api_version'], 1);
    expect(response.$2['api_minor_version'], 1);
    final contracts = response.$2['action_contracts'] as Map;
    expect(
        contracts.keys, containsAll(['open_room', 'set_tone', 'sync_journal']));
    expect(
      (contracts['open_room'] as Map)['allowed_values'],
      contains('reflection_bay'),
    );
    expect((response.$2['limits'] as Map)['body_bytes'], 4096);
    expect(response.$2['cloud_ai'], isFalse);
    expect(response.$2['memory_access'], isFalse);
  });
  test('unsupported versions and errors use typed correlation envelopes',
      () async {
    final unsupported = await request('GET', '/v1/health', apiVersion: '2');
    expect(unsupported.$1, 426);
    expect(unsupported.$2['error'], 'unsupported_api_version');
    final info = unsupported.$2['error_info'] as Map;
    expect(info['retryable'], isFalse);
    expect(info['trace_id'], unsupported.$3.value('x-neura-trace-id'));
  });
  test('proposals never execute, duplicates share a receipt and cannot replay',
      () async {
    final body = {
      'request_id': 'client_1',
      'action': 'set_tone',
      'arguments': {'tone': 'warm_companion'}
    };
    final first = await request('POST', '/v1/proposals', body: body);
    expect(first.$1, 202);
    expect(api.pending, hasLength(1));
    final repeated = await request('POST', '/v1/proposals', body: body);
    expect(repeated.$2, first.$2);
    final proposal = api.takeForApproval(first.$2['id'] as String)!;
    expect(api.canApply(proposal), true);
    expect(api.takeForApproval(proposal.id), null);
    api.finish(proposal, 'denied');
    expect(api.canApply(proposal), false);
    expect((await request('POST', '/v1/proposals', body: body)).$2['status'],
        'denied');
    expect(api.pending, isEmpty);
  });
  test('unknown or extra action arguments are rejected', () async {
    for (final action in ['shell', 'read_file', 'send_cloud_request']) {
      expect(
          (await request('POST', '/v1/proposals', body: {
            'request_id': action,
            'action': action,
            'arguments': {}
          }))
              .$1,
          400);
    }
    expect(
        (await request('POST', '/v1/proposals', body: {
          'request_id': 'x',
          'action': 'set_tone',
          'arguments': {'tone': 'warm_companion', 'command': 'execute'}
        }))
            .$1,
        400);
  });
  test('expired proposals and revoked mode cannot be approved', () async {
    final response = await request('POST', '/v1/proposals',
        body: {'request_id': 'x', 'action': 'sync_journal', 'arguments': {}});
    final proposal = api.takeForApproval(response.$2['id'] as String)!;
    now = now.add(const Duration(minutes: 3));
    expect(api.canApply(proposal), false);
    allowed = false;
    expect((await request('GET', '/v1/health')).$1, 503);
  });
  test('stop revokes session, clears proposals and rotates token', () async {
    final oldToken = api.token;
    await request('POST', '/v1/proposals',
        body: {'request_id': 'x', 'action': 'sync_journal', 'arguments': {}});
    await api.stop();
    expect(api.token, null);
    expect(api.pending, isEmpty);
    await api.start();
    expect(api.token, isNot(oldToken));
  });
  test('active proposal pressure returns typed retry guidance', () async {
    for (var index = 0; index < NeuraLocalApi.maxActiveProposals; index++) {
      final response = await request('POST', '/v1/proposals', body: {
        'request_id': 'active_$index',
        'action': 'sync_journal',
        'arguments': {}
      });
      expect(response.$1, 202);
    }
    final limited = await request('POST', '/v1/proposals', body: {
      'request_id': 'active_overflow',
      'action': 'sync_journal',
      'arguments': {}
    });
    expect(limited.$1, 429);
    expect(limited.$2['error'], 'active_proposal_limit');
    expect((limited.$2['error_info'] as Map)['retryable'], isTrue);
    expect(limited.$3.value('retry-after'), '1');
  });
  test('final receipts are pruned while request-id tombstones prevent replay',
      () async {
    String? firstProposalId;
    for (var index = 0; index < 70; index++) {
      final response = await request('POST', '/v1/proposals', body: {
        'request_id': 'receipt_$index',
        'action': 'sync_journal',
        'arguments': {}
      });
      expect(response.$1, 202);
      firstProposalId ??= response.$2['id'] as String;
      final proposal = api.takeForApproval(response.$2['id'] as String)!;
      api.finish(proposal, 'denied');
      now = now.add(const Duration(minutes: 1));
    }

    final retired = await request('POST', '/v1/proposals', body: {
      'request_id': 'receipt_0',
      'action': 'sync_journal',
      'arguments': {}
    });
    expect(retired.$1, 410);
    expect(retired.$2['error'], 'request_id_retired');
    expect(retired.$2, isNot(contains('id')));
    expect(
      (await request('GET', '/v1/proposals/$firstProposalId')).$1,
      404,
    );
  });
  test('rate limiting returns Retry-After and a retryable error', () async {
    late (int, Map<String, dynamic>, HttpHeaders) response;
    for (var index = 0; index <= NeuraLocalApi.maxRequestsPerMinute; index++) {
      response = await request('GET', '/v1/health');
    }
    expect(response.$1, 429);
    expect(response.$2['error'], 'rate_limited');
    expect((response.$2['error_info'] as Map)['retryable'], isTrue);
    expect(int.parse(response.$3.value('retry-after')!), greaterThan(0));
  });
  test('checked-in OpenAPI contract describes only bounded proposal routes',
      () async {
    final contract = jsonDecode(
      await File('docs/neura-local-api-v1.openapi.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(contract['openapi'], '3.1.0');
    final paths = contract['paths'] as Map;
    expect(paths.keys.toSet(), {
      '/health',
      '/capabilities',
      '/proposals',
      '/proposals/{id}',
    });
    expect(paths.keys, isNot(contains('/execute')));
    expect(paths.keys, isNot(contains('/memory')));

    final components = contract['components'] as Map;
    final responseComponents = components['responses'] as Map;
    for (final path in paths.values.cast<Map>()) {
      for (final operation in path.values.cast<Map>()) {
        final responses = operation['responses'] as Map;
        for (final response in responses.values.cast<Map>()) {
          final reference = response[r'$ref'];
          final resolved = reference is String
              ? responseComponents[reference.split('/').last] as Map
              : response;
          final headers = resolved['headers'] as Map;
          expect(headers, contains('X-Neura-Api-Version'));
          expect(headers, contains('X-Neura-Trace-Id'));
        }
      }
    }
  });
}
