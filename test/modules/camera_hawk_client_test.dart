import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../lib/modules/camera_hawk/camera_hawk_client.dart';

void main() {
  test('explicit sign-in uses fixed loopback and bearer header only', () async {
    final requests = <http.Request>[];
    final client = CameraHawkClient(
      transport: MockClient((r) async {
        requests.add(r);
        expect(r.url.host, '127.0.0.1');
        expect(r.url.port, 8799);
        expect(r.followRedirects, isFalse);
        if (r.url.path.endsWith('/login'))
          return http.Response('{"access_token":"session-secret"}', 200);
        if (r.url.path.endsWith('/logout'))
          return http.Response('{"ok":true}', 200);
        return http.Response(
          '[{"name":"Door","location":"Entry","enabled":true,"rtsp_url":"secret","password_ref":"vault"}]',
          200,
        );
      }),
    );
    expect(requests, isEmpty);
    await client.signIn('viewer', 'password-secret');
    final cameras = await client.cameras();
    expect(cameras.single.name, 'Door');
    expect(requests.last.headers['authorization'], 'Bearer session-secret');
    expect(requests.last.url.query, isEmpty);
    await client.disconnect();
    expect(client.connected, isFalse);
    expect(requests.last.url.path, '/v1/auth/logout');
    await client.dispose();
  });

  test('disconnect revokes a late login instead of restoring access', () async {
    final login = Completer<http.Response>();
    final revoked = <String>[];
    final client = CameraHawkClient(
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/login')) return login.future;
        revoked.add(r.headers['authorization']!);
        return http.Response('{"ok":true}', 200);
      }),
    );
    final pending = client.signIn('viewer', 'password');
    final check = expectLater(pending, throwsStateError);
    await client.disconnect();
    login.complete(http.Response('{"access_token":"late-secret"}', 200));
    await check;
    expect(client.connected, isFalse);
    expect(revoked, ['Bearer late-secret']);
    await client.dispose();
  });

  test('in-flight camera result is discarded on disconnect', () async {
    final response = Completer<http.Response>();
    final client = CameraHawkClient(
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/login'))
          return http.Response('{"access_token":"secret"}', 200);
        if (r.url.path.endsWith('/logout')) return http.Response('{}', 200);
        return response.future;
      }),
    );
    await client.signIn('u', 'p');
    final pending = client.cameras();
    await client.disconnect();
    response.complete(http.Response('[{"name":"Door"}]', 200));
    expect(await pending, isEmpty);
    await client.dispose();
  });

  test('server errors never expose response credentials', () async {
    final client = CameraHawkClient(
      transport: MockClient(
        (_) async =>
            http.Response('password-secret session-secret rtsp://private', 401),
      ),
    );
    try {
      await client.signIn('u', 'p');
      fail('expected failure');
    } catch (error) {
      expect(error.toString(), isNot(contains('password-secret')));
      expect(error.toString(), isNot(contains('session-secret')));
      expect(error.toString(), isNot(contains('rtsp://')));
    }
    await client.dispose();
  });

  test('redirects fail closed', () async {
    final client = CameraHawkClient(
      transport: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://example.com'},
        ),
      ),
    );
    await expectLater(client.signIn('u', 'p'), throwsStateError);
    expect(client.connected, isFalse);
    await client.dispose();
  });

  test('offline logout still discards local authorization', () async {
    final client = CameraHawkClient(
      transport: MockClient((r) async {
        if (r.url.path.endsWith('/login'))
          return http.Response('{"access_token":"secret"}', 200);
        throw StateError('offline');
      }),
    );
    await client.signIn('u', 'p');
    await client.disconnect();
    expect(client.connected, isFalse);
    await expectLater(client.cameras(), throwsStateError);
    await client.dispose();
  });

  test('dispose cannot be followed by another login', () async {
    final client = CameraHawkClient(
      transport: MockClient((_) async {
        fail('no request allowed');
      }),
    );
    await client.dispose();
    await expectLater(client.signIn('u', 'p'), throwsStateError);
  });
}
