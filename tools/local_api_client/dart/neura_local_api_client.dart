import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _rooms = <String>{
  'penthouse',
  'reflection_bay',
  'joy_lounge',
  'mood_den',
  'dream_atrium',
  'legacy_vault',
};

const _tones = <String>{
  'strategist',
  'calm_wellness',
  'warm_companion',
  'cinematic_guide',
  'quiet_private',
};

const _usage = '''
Neura Local App API client

Usage:
  dart run neura_local_api_client.dart health --url <http://127.0.0.1:PORT/v1>
  dart run neura_local_api_client.dart capabilities --url <URL>
  dart run neura_local_api_client.dart propose --url <URL> \\
      --action <open_room|set_tone|sync_journal> [--value <VALUE>] \\
      [--request-id <ID>]
  dart run neura_local_api_client.dart status --url <URL> --id <PROPOSAL_ID>

The token is read from NEURA_LOCAL_API_TOKEN or prompted without echo.
The URL may instead be supplied through NEURA_LOCAL_API_URL.
''';

final class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;
  final Object? body;

  Map<String, Object?> toJson(String command) => {
        'command': command,
        'status_code': statusCode,
        'body': body,
        'network_error': false,
      };
}

final class NeuraLocalApiClient {
  NeuraLocalApiClient(this.baseUri, this.token) {
    // Keep the callback assignment separate so its expression body cannot
    // absorb the following cascade sections.
    _http.findProxy = (_) => 'DIRECT';
    _http
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 5);
  }

  final Uri baseUri;
  final String token;
  final HttpClient _http = HttpClient();

  Future<ApiResponse> get(String path) => _request('GET', path);

  Future<ApiResponse> post(String path, Map<String, Object?> body) =>
      _request('POST', path, body: body);

  Future<ApiResponse> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_/-]+$').hasMatch(path)) {
      throw const FormatException('Invalid API path.');
    }
    final uri = baseUri.resolve(path.replaceFirst(RegExp(r'^/+'), ''));
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.port != baseUri.port) {
      throw const FormatException('Request escaped the loopback API origin.');
    }

    final request = method == 'GET'
        ? await _http.getUrl(uri)
        : await _http.postUrl(uri);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(const Duration(seconds: 10));
    final responseText = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 10));
    Object? responseBody;
    if (responseText.trim().isNotEmpty) {
      try {
        responseBody = jsonDecode(responseText);
      } on FormatException {
        responseBody = responseText;
      }
    }
    return ApiResponse(response.statusCode, responseBody);
  }

  void close() => _http.close(force: true);
}

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.contains('--help') ||
      arguments.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  NeuraLocalApiClient? client;
  try {
    final command = arguments.first.toLowerCase();
    if (!{'health', 'capabilities', 'propose', 'status'}.contains(command)) {
      throw FormatException('Unknown command "$command".\n$_usage');
    }
    final options = _parseOptions(arguments.skip(1).toList(growable: false));
    final allowedOptions = switch (command) {
      'health' || 'capabilities' => {'url'},
      'propose' => {'url', 'action', 'value', 'request-id'},
      'status' => {'url', 'id'},
      _ => <String>{},
    };
    final unknown = options.keys.where((key) => !allowedOptions.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unsupported option --${unknown.first} for $command.',
      );
    }

    final rawUrl =
        options['url'] ?? Platform.environment['NEURA_LOCAL_API_URL'];
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      throw const FormatException(
        'Pass --url or set NEURA_LOCAL_API_URL.',
      );
    }
    final token = _readToken();
    final baseUri = _parseBaseUri(rawUrl);
    client = NeuraLocalApiClient(baseUri, token);

    late final ApiResponse response;
    switch (command) {
      case 'health':
        response = await client.get('health');
        break;
      case 'capabilities':
        response = await client.get('capabilities');
        break;
      case 'propose':
        response = await client.post('proposals', _proposal(options));
        break;
      case 'status':
        final id = options['id'];
        if (id == null || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
          throw const FormatException(
            '--id must be the proposal ID returned by Neura.',
          );
        }
        response = await client.get('proposals/$id');
        break;
      default:
        throw StateError('Unreachable command.');
    }

    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert(response.toJson(command)));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      exitCode = 3;
    }
  } on FormatException catch (error) {
    stderr.writeln('Neura local API client: ${error.message}');
    exitCode = 2;
  } on SocketException catch (error) {
    stderr.writeln(
      'Neura local API client: network error (${error.runtimeType}).',
    );
    exitCode = 4;
  } on HttpException catch (error) {
    stderr.writeln(
      'Neura local API client: HTTP transport error (${error.runtimeType}).',
    );
    exitCode = 4;
  } on TimeoutException catch (error) {
    stderr.writeln('Neura local API client: timeout (${error.runtimeType}).');
    exitCode = 4;
  } finally {
    client?.close();
  }
}

Map<String, String> _parseOptions(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final option = arguments[index];
    if (!option.startsWith('--') || option.length < 3) {
      throw FormatException('Expected an option, found "$option".');
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('Option $option needs a value.');
    }
    final name = option.substring(2);
    if (options.containsKey(name)) {
      throw FormatException('Option $option was supplied more than once.');
    }
    options[name] = arguments[index + 1];
  }
  return options;
}

Uri _parseBaseUri(String input) {
  final match = RegExp(
    r'^http://127\.0\.0\.1:([0-9]{1,5})/v1/?$',
  ).firstMatch(input.trim());
  if (match == null) {
    throw const FormatException(
      'URL must be http://127.0.0.1:<port>/v1.',
    );
  }
  final port = int.parse(match.group(1)!);
  if (port < 1 || port > 65535) {
    throw const FormatException('URL port must be between 1 and 65535.');
  }
  return Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/v1/');
}

String _readToken() {
  final environmentToken = Platform.environment['NEURA_LOCAL_API_TOKEN'];
  if (environmentToken != null && environmentToken.isNotEmpty) {
    return environmentToken;
  }
  if (!stdin.hasTerminal) {
    throw const FormatException(
      'Set NEURA_LOCAL_API_TOKEN when standard input is not a terminal.',
    );
  }

  stdout.write('Neura session token: ');
  var echoChanged = false;
  try {
    stdin.echoMode = false;
    echoChanged = true;
    final token = stdin.readLineSync();
    if (token == null || token.isEmpty) {
      throw const FormatException('A session token is required.');
    }
    return token;
  } finally {
    if (echoChanged) stdin.echoMode = true;
    stdout.writeln();
  }
}

Map<String, Object?> _proposal(Map<String, String> options) {
  final action = options['action'];
  if (!{'open_room', 'set_tone', 'sync_journal'}.contains(action)) {
    throw const FormatException(
      '--action must be open_room, set_tone, or sync_journal.',
    );
  }
  final generatedId =
      'dart-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 31)}';
  final requestId = options['request-id'] ?? generatedId;
  if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(requestId)) {
    throw const FormatException(
      '--request-id must contain 1-64 letters, numbers, underscores, or hyphens.',
    );
  }

  final value = options['value'];
  late final Map<String, Object?> proposalArguments;
  switch (action) {
    case 'open_room':
      if (!_rooms.contains(value)) {
        throw FormatException(
          '--value must be a known room: ${_rooms.join(', ')}.',
        );
      }
      proposalArguments = {'room': value};
      break;
    case 'set_tone':
      if (!_tones.contains(value)) {
        throw FormatException(
          '--value must be a known tone: ${_tones.join(', ')}.',
        );
      }
      proposalArguments = {'tone': value};
      break;
    case 'sync_journal':
      if (value != null) {
        throw const FormatException('sync_journal does not accept --value.');
      }
      proposalArguments = {};
      break;
    default:
      throw StateError('Unreachable proposal action.');
  }

  return {
    'request_id': requestId,
    'action': action,
    'arguments': proposalArguments,
  };
}
