import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class TimelineVault {
  TimelineVault._();
  static final TimelineVault instance = TimelineVault._();

  static const _maxTailLines = 500;
  File? _events;
  File? _index;
  Future<void> _writeQueue = Future.value();
  int _count = 0;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}${Platform.pathSeparator}neura${Platform.pathSeparator}timeline');
    await directory.create(recursive: true);
    _events = File('${directory.path}${Platform.pathSeparator}events.jsonl');
    _index = File('${directory.path}${Platform.pathSeparator}tail-index.json');
    if (!await _events!.exists()) await _events!.create(recursive: true);
    if (await _index!.exists()) {
      try {
        final json = jsonDecode(await _index!.readAsString()) as Map<String, dynamic>;
        _count = (json['count'] as num?)?.toInt() ?? 0;
      } catch (_) {
        _count = await _events!.readAsLines().then((lines) => lines.length);
      }
    }
    _initialized = true;
  }

  Future<void> append(
    String kind, {
    Map<String, Object?> data = const {},
    String source = 'neura_os',
  }) {
    final completion = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        if (!_initialized) await initialize();
        final record = <String, Object?>{
          'v': 1,
          'seq': ++_count,
          'ts': DateTime.now().toUtc().toIso8601String(),
          'kind': kind,
          'source': source,
          'data': data,
        };
        await _events!.writeAsString(
          '${jsonEncode(record)}\n',
          mode: FileMode.append,
          flush: true,
        );
        await _index!.writeAsString(jsonEncode({
          'v': 1,
          'count': _count,
          'last_seq': _count,
          'last_ts': record['ts'],
        }), flush: true);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<List<Map<String, dynamic>>> tail({int maxLines = 100}) async {
    await _writeQueue;
    if (!_initialized) await initialize();
    final lines = await _events!.readAsLines();
    final take = maxLines.clamp(1, _maxTailLines).toInt();
    final start = lines.length > take ? lines.length - take : 0;
    return lines.sublist(start).map((line) {
      try {
        return Map<String, dynamic>.from(jsonDecode(line) as Map);
      } catch (_) {
        return <String, dynamic>{'kind': 'corrupt_record', 'raw': line};
      }
    }).toList(growable: false);
  }

  Future<String> exportCopy() async {
    await _writeQueue;
    if (!_initialized) await initialize();
    final support = await getApplicationSupportDirectory();
    final exports = Directory('${support.path}${Platform.pathSeparator}neura${Platform.pathSeparator}exports');
    await exports.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File('${exports.path}${Platform.pathSeparator}neura-timeline-$stamp.jsonl');
    await _events!.copy(target.path);
    return target.path;
  }
}
