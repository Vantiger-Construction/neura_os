import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_local_api.dart';

void main() {
  late NeuraLocalApi api;
  late HttpClient client;
  var allowed = true;
  var now = DateTime.utc(2026, 9, 18);
  Future<(int, Map<String, dynamic>)> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    bool browser = false,
  }) async {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${api.port}$path'));
    if (authenticated) req.headers.set('authorization', 'Bearer ${api.token}');
    if (browser) req.headers.set('origin', 'https://example.com');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    return (
      response.statusCode,
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>
    );
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
    expect((await request('POST', '/v1/execute', body: {})).$1, 404);
    expect((await request('GET', '/v1/memory')).$1, 404);
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
}
