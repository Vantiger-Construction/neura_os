import 'dart:convert';

import '../neura_avatar_runtime_bridge.dart';

/// Launcher-supplied settings for publishing avatar presence to the opt-in
/// `neura_api` presence relay, which the Unity presence prototype subscribes
/// to.
///
/// Both values come only from this process's environment, set for child
/// processes by `tools/Start-NeuraPresenceBridge.ps1`. When neither is set the
/// relay is off and nothing connects. The session token is never persisted,
/// logged or included in [toString].
class NeuraPresenceRelayConfig {
  const NeuraPresenceRelayConfig._(this.endpoint, this._token);

  static const String addressVariable = 'NEURA_PRESENCE_RELAY_ADDR';
  static const String tokenVariable = 'NEURA_PRESENCE_TOKEN';

  final Uri endpoint;
  final String _token;

  /// The `Authorization` header value for the relay connection.
  String get authorization => 'Bearer $_token';

  /// Returns null unless both values are present and valid: a numeric
  /// loopback `host:port` (no DNS names) and a 64-character hex token.
  static NeuraPresenceRelayConfig? fromEnvironment(
    Map<String, String> environment,
  ) {
    final address = environment[addressVariable];
    final token = environment[tokenVariable];
    if (address == null || token == null) return null;
    final endpoint = loopbackEndpoint(address);
    if (endpoint == null || !isSessionToken(token)) return null;
    return NeuraPresenceRelayConfig._(endpoint, token);
  }

  static final RegExp _tokenPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _ipv4Loopback = RegExp(
    r'^127\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.'
    r'(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.'
    r'(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
  );
  static final RegExp _port = RegExp(r'^[1-9]\d{0,4}$');

  static bool isSessionToken(String token) => _tokenPattern.hasMatch(token);

  static Uri? loopbackEndpoint(String address) {
    if (address.length > 32) return null;
    final colon = address.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = address.substring(0, colon);
    final portText = address.substring(colon + 1);
    if (!_port.hasMatch(portText)) return null;
    final port = int.parse(portText);
    if (port > 65535) return null;
    if (host != '[::1]' && !_ipv4Loopback.hasMatch(host)) return null;
    return Uri.parse('ws://$host:$port/');
  }

  @override
  String toString() => 'NeuraPresenceRelayConfig($endpoint)';
}

/// Relay message publishing [snapshot], the same content-free v1 shape the
/// in-process avatar renderers consume.
String neuraPresencePublishMessage(NeuraAvatarRuntimeSnapshot snapshot) =>
    jsonEncode(<String, Object>{
      'v': 1,
      'kind': 'presence_publish',
      'data': snapshot.toJson(),
    });

/// Relay message withdrawing the published snapshot (Unity returns to safe
/// Still).
const String neuraPresenceClearMessage =
    '{"v":1,"kind":"presence_clear","data":{}}';
