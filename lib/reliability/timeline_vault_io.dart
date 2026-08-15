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
  bool _suspendedForDataWipe = false;

  Future<void> initialize() async {
    if (_suspendedForDataWipe) return;
    if (_initialized) return;
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}timeline',
    );
    await directory.create(recursive: true);
    _events = File('${directory.path}${Platform.pathSeparator}events.jsonl');
    _index = File('${directory.path}${Platform.pathSeparator}tail-index.json');
    if (!await _events!.exists()) await _events!.create(recursive: true);
    var indexedCount = 0;
    if (await _index!.exists()) {
      try {
        final json =
            jsonDecode(await _index!.readAsString()) as Map<String, dynamic>;
        indexedCount = (json['count'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    final lines = await _events!.readAsLines();
    var eventCount = 0;
    var lastSequence = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      eventCount += 1;
      try {
        final record = jsonDecode(line) as Map<String, dynamic>;
        final sequence = (record['seq'] as num?)?.toInt() ?? 0;
        if (sequence > lastSequence) lastSequence = sequence;
      } catch (_) {
        // Corrupt records still consume a sequence slot.
      }
    }
    _count = [indexedCount, eventCount, lastSequence]
        .reduce((left, right) => left > right ? left : right);
    _initialized = true;
  }

  Future<void> append(
    String kind, {
    Map<String, Object?> data = const {},
    String source = 'neura_os',
  }) {
    if (_suspendedForDataWipe) return Future<void>.value();
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
        await _writeIndex({
          'v': 1,
          'count': _count,
          'last_seq': _count,
          'last_ts': record['ts'],
        });
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<List<Map<String, dynamic>>> tail({int maxLines = 100}) async {
    if (_suspendedForDataWipe) return const <Map<String, dynamic>>[];
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
    if (_suspendedForDataWipe) {
      throw StateError('Timeline is suspended until Neura restarts.');
    }
    await _writeQueue;
    if (!_initialized) await initialize();
    final support = await getApplicationSupportDirectory();
    final exports = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}exports',
    );
    await exports.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File(
      '${exports.path}${Platform.pathSeparator}'
      'neura-timeline-$stamp.jsonl',
    );
    await _events!.copy(target.path);
    return target.path;
  }

  /// Drains pending writes and releases cached paths before local data is
  /// deleted. A later append will initialize a fresh, empty vault.
  Future<void> resetAfterDataWipe() async {
    _suspendedForDataWipe = true;
    await _writeQueue;
    _events = null;
    _index = null;
    _count = 0;
    _initialized = false;
  }

  Future<void> _writeIndex(Map<String, Object?> value) async {
    final index = _index!;
    final temporary = File('${index.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await index.exists()) await index.delete();
    await temporary.rename(index.path);
  }
}
