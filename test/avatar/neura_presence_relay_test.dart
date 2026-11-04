import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/neura_avatar_runtime_bridge.dart';
import 'package:neuro_companion/avatar/presence_relay/neura_presence_relay_config.dart';
import 'package:neuro_companion/avatar/presence_relay/neura_presence_relay_io.dart';
import 'package:neuro_companion/neura_shell/models/neura_room_presence_profile.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';

const _token =
    'abababababababababababababababababababababababababababababababab';

NeuraAvatarRuntimeSnapshot _snapshot(NeuraPresencePhase phase) =>
    NeuraAvatarRuntimeSnapshot(
      roomId: 'mood_den',
      phase: phase,
      stance: NeuraRoomStance.grounding,
      motion: NeuraCompanionMotion.subtle,
      scale: NeuraCompanionScale.standard,
      safeMode: false,
    );

/// A loopback stand-in for neura_api's relay that records what it receives.
class _Relay {
  _Relay._(this._server);

  final HttpServer _server;
  final List<String?> authorizations = <String?>[];
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<WebSocket> _sockets = <WebSocket>[];

  static Future<_Relay> start() async {
    final relay = _Relay._(await HttpServer.bind('127.0.0.1', 0));
    relay._server.listen((request) async {
      relay.authorizations
          .add(request.headers.value(HttpHeaders.authorizationHeader));
      final socket = await WebSocketTransformer.upgrade(request);
      relay._sockets.add(socket);
      socket.listen(
        (frame) => relay._messages
            .add(jsonDecode(frame as String) as Map<String, dynamic>),
      );
    });
    return relay;
  }

  String get address => '127.0.0.1:${_server.port}';

  Future<Map<String, dynamic>> next() =>
      _messages.stream.first.timeout(const Duration(seconds: 5));

  Future<void> dropConnections() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    _sockets.clear();
  }

  Future<void> close() async {
    await dropConnections();
    await _server.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every HttpClient request with 400. These tests
  // only reach their own in-process loopback relay, so use real sockets.
  HttpOverrides.global = null;

  group('NeuraPresenceRelayConfig', () {
    NeuraPresenceRelayConfig? config(String? address, String? token) {
      final environment = <String, String>{};
      if (address != null) {
        environment[NeuraPresenceRelayConfig.addressVariable] = address;
      }
      if (token != null) {
        environment[NeuraPresenceRelayConfig.tokenVariable] = token;
      }
      return NeuraPresenceRelayConfig.fromEnvironment(environment);
    }

    test('is off unless the launcher set both values', () {
      expect(config(null, null), isNull);
      expect(config('127.0.0.1:8790', null), isNull);
      expect(config(null, _token), isNull);
    });

    test('accepts numeric loopback endpoints only', () {
      expect(
        config('127.0.0.1:8790', _token)!.endpoint.toString(),
        'ws://127.0.0.1:8790/',
      );
      expect(config('[::1]:65535', _token), isNotNull);
      for (final address in <String>[
        'localhost:8790',
        '0.0.0.0:8790',
        '192.168.1.5:8790',
        '127.0.0.1',
        '127.0.0.1:0',
        '127.0.0.1:65536',
        '127.0.0.1:08790',
        '127.0.0.01:8790',
        '127.0.0.256:8790',
        '[::]:8790',
        'evil.example:80',
      ]) {
        expect(config(address, _token), isNull, reason: address);
      }
    });

    test('requires a 64-character hex session token and never prints it', () {
      expect(config('127.0.0.1:8790', _token.substring(1)), isNull);
      expect(config('127.0.0.1:8790', '${_token.substring(1)}g'), isNull);
      final valid = config('127.0.0.1:8790', _token.toUpperCase())!;
      expect(valid.authorization, 'Bearer ${_token.toUpperCase()}');
      expect(valid.toString(), isNot(contains(_token.toUpperCase())));
    });

    test('publish message carries exactly the v1 snapshot', () {
      final snapshot = _snapshot(NeuraPresencePhase.safeMode);
      final message = jsonDecode(neuraPresencePublishMessage(snapshot)) as Map;
      expect(message['kind'], 'presence_publish');
      expect(message['data'], snapshot.toJson());
      expect((message['data'] as Map)['phase'], 'safeMode');
    });
  });

  group('NeuraPresenceRelayPublisher', () {
    late _Relay relay;
    late ValueNotifier<NeuraAvatarRuntimeSnapshot?> source;
    late NeuraPresenceRelayPublisher publisher;

    setUp(() async {
      relay = await _Relay.start();
      source = ValueNotifier<NeuraAvatarRuntimeSnapshot?>(
        _snapshot(NeuraPresencePhase.thinking),
      );
      publisher = NeuraPresenceRelayPublisher(
        config: NeuraPresenceRelayConfig.fromEnvironment(<String, String>{
          NeuraPresenceRelayConfig.addressVariable: relay.address,
          NeuraPresenceRelayConfig.tokenVariable: _token,
        })!,
        source: source,
        heartbeat: const Duration(hours: 1),
        maxBackoff: const Duration(seconds: 1),
      );
    });

    tearDown(() async {
      await publisher.stop();
      await relay.close();
    });

    test('authenticates and publishes the current snapshot on connect',
        () async {
      final first = relay.next();
      publisher.start();
      final message = await first;
      expect(relay.authorizations.single, 'Bearer $_token');
      expect(message['kind'], 'presence_publish');
      expect((message['data'] as Map)['phase'], 'thinking');
    });

    test('publishes changes and withdraws presence when hidden or stopped',
        () async {
      final connected = relay.next();
      publisher.start();
      await connected;

      final changed = relay.next();
      source.value = _snapshot(NeuraPresencePhase.speaking);
      expect(((await changed)['data'] as Map)['phase'], 'speaking');

      final cleared = relay.next();
      source.value = null;
      expect((await cleared)['kind'], 'presence_clear');

      source.value = _snapshot(NeuraPresencePhase.idle);
      await relay.next();
      final hidden = relay.next();
      publisher.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect((await hidden)['kind'], 'presence_clear');

      // Another window taking focus (inactive) keeps Neura present.
      final back = relay.next();
      publisher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect((await back)['kind'], 'presence_publish');

      final stopped = relay.next();
      await publisher.stop();
      expect((await stopped)['kind'], 'presence_clear');
    });

    test('reconnects and republishes after the relay drops it', () async {
      final connected = relay.next();
      publisher.start();
      await connected;
      final republished = relay.next();
      await relay.dropConnections();
      expect((await republished)['kind'], 'presence_publish');
      expect(relay.authorizations, hasLength(2));
    });
  });
}
