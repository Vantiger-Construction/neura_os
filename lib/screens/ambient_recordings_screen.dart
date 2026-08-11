import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/memory/memory_crypto.dart';

class _RecordingEntry {
  final String filename;
  final int timestampMs;
  final int durationMs;
  final int sizeBytes;

  _RecordingEntry({
    required this.filename,
    required this.timestampMs,
    required this.durationMs,
    required this.sizeBytes,
  });

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);
}

/// Lists, plays back, and deletes Neura's voice-activity-triggered
/// recordings (see AmbientListeningService). Reads the unencrypted
/// `index.jsonl` sidecar for metadata so the list can render without
/// decrypting every clip up front -- each clip's audio bytes are only
/// decrypted when the user actually taps play.
class AmbientRecordingsScreen extends StatefulWidget {
  const AmbientRecordingsScreen({super.key});

  @override
  State<AmbientRecordingsScreen> createState() =>
      _AmbientRecordingsScreenState();
}

class _AmbientRecordingsScreenState extends State<AmbientRecordingsScreen> {
  bool _loading = true;
  List<_RecordingEntry> _entries = [];
  final _player = AudioPlayer();
  String? _playingFilename;
  MemoryCrypto? _crypto;
  String? _tempPlaybackPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    _cleanupTempFile();
    super.dispose();
  }

  Future<Directory> _dir() async {
    final d = await getApplicationDocumentsDirectory();
    return Directory('${d.path}${Platform.pathSeparator}neura_ambient_audio');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = <_RecordingEntry>[];
    try {
      final dir = await _dir();
      final indexFile =
          File('${dir.path}${Platform.pathSeparator}index.jsonl');
      if (await indexFile.exists()) {
        final lines = await indexFile.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final map = jsonDecode(line) as Map<String, dynamic>;
            entries.add(_RecordingEntry(
              filename: map['filename'] as String,
              timestampMs: map['timestampMs'] as int,
              durationMs: map['durationMs'] as int,
              sizeBytes: map['sizeBytes'] as int,
            ));
          } catch (_) {
            // Skip a corrupt line rather than failing the whole list.
          }
        }
      }
    } catch (_) {
      // No recordings dir yet, or unreadable -- show an empty list.
    }
    entries.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<MemoryCrypto> _ensureCrypto() async {
    return _crypto ??= await MemoryCrypto.demo();
  }

  Future<void> _cleanupTempFile() async {
    final path = _tempPlaybackPath;
    _tempPlaybackPath = null;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _play(_RecordingEntry entry) async {
    try {
      await _player.stop();
      await _cleanupTempFile();

      final dir = await _dir();
      final file = File('${dir.path}${Platform.pathSeparator}${entry.filename}');
      final encrypted = await file.readAsBytes();
      final crypto = await _ensureCrypto();
      final wav = await crypto.decryptBytes(encrypted);

      setState(() => _playingFilename = entry.filename);

      try {
        // Preferred: play straight from memory, no plaintext file at all.
        await _player.play(BytesSource(wav));
      } catch (_) {
        // Fallback: some platform audio backends can't take raw bytes --
        // write a short-lived plaintext temp file (NOT the encrypted
        // storage folder), played then deleted immediately after.
        final tempDir = await getTemporaryDirectory();
        final tempPath =
            '${tempDir.path}${Platform.pathSeparator}amb_playback_${entry.timestampMs}.wav';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(wav, flush: true);
        _tempPlaybackPath = tempPath;
        await _player.play(DeviceFileSource(tempPath));
      }

      unawaited(_player.onPlayerComplete.first.then((_) async {
        if (mounted) setState(() => _playingFilename = null);
        await _cleanupTempFile();
      }));
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingFilename = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play this clip: $e')),
      );
    }
  }

  Future<void> _delete(_RecordingEntry entry) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}${Platform.pathSeparator}${entry.filename}');
      if (await file.exists()) await file.delete();

      final remaining = _entries.where((e) => e.filename != entry.filename);
      final indexFile =
          File('${dir.path}${Platform.pathSeparator}index.jsonl');
      final buffer = StringBuffer();
      for (final e in remaining) {
        buffer.writeln(jsonEncode({
          'filename': e.filename,
          'timestampMs': e.timestampMs,
          'durationMs': e.durationMs,
          'sizeBytes': e.sizeBytes,
        }));
      }
      await indexFile.writeAsString(buffer.toString(), flush: true);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _entries = _entries.where((e) => e.filename != entry.filename).toList();
    });
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).round();
    return '${seconds}s';
  }

  String _formatTimestamp(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recorded Clips')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing recorded yet. Turn on "Listen for speech and record clips" in Privacy & Safety to start.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final entry = _entries[i];
                      final playing = _playingFilename == entry.filename;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            playing ? Icons.pause_circle : Icons.play_circle_outline,
                          ),
                          title: Text(_formatTimestamp(entry.timestamp)),
                          subtitle: Text(
                              '${_formatDuration(entry.durationMs)} · ${(entry.sizeBytes / 1024).round()} KB'),
                          onTap: () => _play(entry),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(entry),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
