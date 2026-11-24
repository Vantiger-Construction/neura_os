import 'dart:async';
import 'dart:io';

import 'day_companion_cues.dart';

/// One client-configured Home Assistant automation. The webhook is a secret,
/// kept in RAM. The hub owns the actual device and action parameters.
class HomeAction {
  HomeAction._(this.label, this.endpoint, this.cue);
  final PenthouseCue? cue;
  final String label;
  final Uri endpoint;

  factory HomeAction.configure(String name, String url, {PenthouseCue? cue}) {
    final label = name.trim();
    final uri = Uri.tryParse(url.trim());
    if (label.length < 3 ||
        label.length > 72 ||
        !RegExp(r"^[A-Za-z0-9][A-Za-z0-9 '°.-]*$").hasMatch(label) ||
        uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        !RegExp(r'^/api/webhook/[A-Za-z0-9_-]{16,128}$').hasMatch(uri.path)) {
      throw const FormatException(
          'Enter an action name and its local Home Assistant webhook URL.');
    }
    final ip = InternetAddress.tryParse(uri.host);
    if (ip != null ? !_local(ip) : !uri.host.endsWith('.local')) {
      throw const FormatException(
          'Use the local IP address or .local name of your hub.');
    }
    return HomeAction._(label, uri, cue);
  }

  static bool _local(InternetAddress ip) {
    final b = ip.rawAddress;
    if (ip.isLoopback) return true;
    if (b.length == 16) return (b[0] & 0xfe) == 0xfc;
    return b[0] == 10 ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31);
  }

  bool matches(String phrase) {
    final words =
        phrase.trim().toLowerCase().replaceFirst(RegExp(r'[.!?]+$'), '');
    return words.replaceFirst(RegExp(r'^(?:hey )?neura[, ]+'), '') ==
            label.toLowerCase() &&
        RegExp(r'^(?:hey )?neura[, ]+').hasMatch(words);
  }

  /// Pin the resolved LAN address for this connection. HTTPS still verifies
  /// the original hostname. No proxy, redirects, retries or speech payload.
  Future<bool> send(HttpClient client,
      {required bool Function() current}) async {
    final uri = endpoint;
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 4);
    client.connectionFactory = (uri, _, __) async {
      final literal = InternetAddress.tryParse(uri.host);
      final ips =
          literal == null ? await InternetAddress.lookup(uri.host) : [literal];
      final address = ips.where(_local).firstOrNull;
      if (!current() || address == null) {
        throw const SocketException('Local hub unavailable');
      }
      final raw = await Socket.startConnect(address, uri.port);
      if (uri.scheme == 'http') return raw;
      Socket? negotiating;
      var cancelled = false;
      final secure = raw.socket.then((s) async {
        negotiating = s;
        try {
          if (cancelled || !current()) throw const SocketException('Cancelled');
          return await SecureSocket.secure(s, host: uri.host);
        } catch (_) {
          s.destroy();
          rethrow;
        }
      });
      return ConnectionTask.fromSocket(secure, () {
        cancelled = true;
        negotiating?.destroy();
        raw.cancel();
      });
    };
    if (!current()) return false;
    final req = await client.openUrl('PUT', uri);
    req.followRedirects = false;
    if (!current()) {
      req.abort();
      return false;
    }
    req.contentLength = 0;
    final response = await req.close();
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
