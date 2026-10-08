import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Foreground, user-initiated Camera Hawk v3.7 viewer session.
/// No credential persistence, camera URLs, media bytes, cloud or polling.
class CameraHawkClient {
  CameraHawkClient({http.Client? transport})
      : _transport = transport ?? http.Client();
  static final dashboardUri = Uri.parse('http://127.0.0.1:8799/');
  final http.Client _transport;
  String? _token;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _login;
  bool get connected => !_closed && _token != null;

  Future<dynamic> _request(
    String method,
    String path, {
    String? token,
    Map<String, String>? body,
  }) async {
    final request = http.Request(method, dashboardUri.resolve(path))
      ..followRedirects = false;
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response =
        await _transport.send(request).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Never surface server text, credentials or request details to logs/UI.
      await response.stream.listen((_) {}).cancel();
      throw StateError('Camera Hawk request failed.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 10),
    )) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw StateError('Camera Hawk response is too large.');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<void> signIn(String username, String password) {
    if (_closed || _login != null || connected) {
      return Future.error(StateError('Camera Hawk session is unavailable.'));
    }
    final generation = _generation;
    final future = _signIn(username, password, generation);
    _login = future;
    return future.whenComplete(() => _login = null);
  }

  Future<void> _signIn(String username, String password, int generation) async {
    final result = await _request(
      'POST',
      '/v1/auth/login',
      body: {'username': username, 'password': password},
    );
    final token = result is Map ? result['access_token'] : null;
    if (token is! String || token.isEmpty) {
      throw StateError('Camera Hawk sign-in failed.');
    }
    if (_closed || generation != _generation) {
      await _revoke(token);
      throw StateError('Camera Hawk session was closed.');
    }
    _token = token;
  }

  Future<List<CameraHawkCamera>> cameras() async {
    final token = _token;
    final generation = _generation;
    if (_closed || token == null) throw StateError('Sign in to Camera Hawk.');
    final result = await _request('GET', '/v1/vision/cameras', token: token);
    if (_closed || generation != _generation) return [];
    if (result is! List) throw StateError('Camera Hawk response is invalid.');
    return result
        .whereType<Map>()
        .map(
          (m) => CameraHawkCamera(
            name: m['name'] is String ? m['name'] as String : 'Camera',
            location: m['location'] is String ? m['location'] as String : '',
            enabled: m['enabled'] == true,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _revoke(String token) async {
    try {
      await _request('POST', '/v1/auth/logout', token: token);
    } catch (_) {
      // Local authorization is discarded even if the service is offline.
      // Remote revocation is best effort; Camera Hawk enforces token expiry.
    }
  }

  Future<void> disconnect() async {
    _generation++;
    final token = _token;
    _token = null;
    if (token != null) await _revoke(token);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await disconnect();
    try {
      await _login;
    } catch (_) {}
    _transport.close();
  }
}

class CameraHawkCamera {
  const CameraHawkCamera({
    required this.name,
    required this.location,
    required this.enabled,
  });
  final String name;
  final String location;
  final bool enabled;
}
