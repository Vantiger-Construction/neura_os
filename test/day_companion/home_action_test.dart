import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/day_companion/home_action.dart';

void main() {
  const path = '/api/webhook/synthetic_test_only_1234';
  test('requires one local webhook and an addressed exact spoken name', () {
    final action = HomeAction.configure(
        'Desk lamp on', 'http://homeassistant.local:8123$path');
    expect(action.matches('Hey Neura, desk lamp on.'), isTrue);
    expect(action.matches('desk lamp on'), isFalse);
    expect(action.matches('Neura, desk lamp on and off'), isFalse);
    for (final url in [
      'https://example.org$path',
      'https://8.8.8.8$path',
      'https://user@homeassistant.local$path',
      'http://127.0.0.1$path?extra',
      'http://127.0.0.1$path#extra',
      'http://192.168.1.2/api/services/light/turn_on',
    ]) {
      expect(() => HomeAction.configure('Desk lamp on', url),
          throwsFormatException);
    }
  });

  test(
      'sends one empty PUT on approval and leaves redirects and retries to the user',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    server.listen((r) async {
      requests.add(
          '${r.method} ${r.uri.path} ${await utf8.decoder.bind(r).join()}');
      if (requests.length == 1) {
        r.response.statusCode = 307;
        r.response.headers.set('location', '/elsewhere');
      }
      await r.response.close();
    });
    final action = HomeAction.configure(
        'Desk light on', 'http://127.0.0.1:${server.port}$path');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    expect(await action.send(client, current: () => false), isFalse);
    expect(requests, isEmpty);
    expect(await action.send(client, current: () => true), isFalse);
    expect(requests, ['PUT $path ']);
    expect(await action.send(client, current: () => true), isTrue);
    expect(requests, ['PUT $path ', 'PUT $path ']);
  });
}
