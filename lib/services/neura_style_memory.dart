import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/memory/memory_crypto.dart';
import '../startup/neura_prefs_cache.dart';

/// One exchange the user marked as a reply they liked.
class NeuraLikedReply {
  final String prompt;
  final String reply;
  final DateTime at;

  const NeuraLikedReply({
    required this.prompt,
    required this.reply,
    required this.at,
  });

  Map<String, dynamic> toJson() =>
      {'p': prompt, 'r': reply, 'at': at.toIso8601String()};

  static NeuraLikedReply? fromJson(Object? value) {
    if (value is! Map) return null;
    final prompt = value['p'];
    final reply = value['r'];
    final at = DateTime.tryParse('${value['at']}');
    if (prompt is! String || reply is! String || at == null) return null;
    if (reply.isEmpty || reply.length > NeuraStyleMemory.maxReplyChars) {
      return null;
    }
    return NeuraLikedReply(prompt: prompt, reply: reply, at: at);
  }
}

/// Learns how this person likes Neura to answer, from their own thumbs up
/// and thumbs down, without retraining anything.
///
/// Liked exchanges and rating word counts are encrypted with the device
/// memory key and stay on this device. They shape only the on-device model's
/// prompt ([promptSection]), as tone-and-length examples, never as facts.
class NeuraStyleMemory {
  NeuraStyleMemory({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    DateTime Function()? now,
  })  : _encrypt = encrypt ??
            ((json) async => (await MemoryCrypto.demo()).encryptJson(json)),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _now = now ?? DateTime.now;

  static final NeuraStyleMemory instance = NeuraStyleMemory();

  @visibleForTesting
  static const storageKey = 'neura.style_memory.v1';
  static const maxLiked = 10;
  static const maxPromptChars = 200;
  static const maxReplyChars = 500;
  static const maxRatings = 40;

  /// The whole prompt section stays within this many UTF-8 bytes.
  static const maxSectionBytes = 900;

  static const _header = 'Replies this person liked before. Match their tone '
      'and length, not their content:';

  final Future<String> Function(Map<String, dynamic>) _encrypt;
  final Future<Map<String, dynamic>> Function(String) _decrypt;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<_StyleState> _read() async {
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return _StyleState([], []);
    final json = await _decrypt(blob);
    final liked = json['liked'];
    final ratings = json['ratings'];
    return _StyleState(
      liked is List
          ? liked
              .map(NeuraLikedReply.fromJson)
              .whereType<NeuraLikedReply>()
              .toList()
          : [],
      ratings is List
          ? ratings
              .whereType<List>()
              .where((r) => r.length == 2 && r[0] is bool && r[1] is int)
              .map((r) => (liked: r[0] as bool, words: r[1] as int))
              .toList()
          : [],
    );
  }

  Future<void> _write(_StyleState state) async {
    final blob = await _encrypt({
      'liked': [for (final pair in state.liked) pair.toJson()],
      'ratings': [
        for (final r in state.ratings) [r.liked, r.words],
      ],
    });
    if (!await NeuraPrefsCache.prefs.setString(storageKey, blob)) {
      throw StateError('Your rating could not be saved.');
    }
  }

  static String _clip(String text, int max) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max - 1)}…';
  }

  static int _words(String text) => RegExp(r'\S+').allMatches(text).length;

  /// Records a thumbs up ([liked]) or down for [reply] to [prompt].
  Future<void> rate({
    required String prompt,
    required String reply,
    required bool liked,
  }) =>
      _serial(() async {
        final clean = reply.trim();
        if (clean.isEmpty) return;
        final state = await _read();
        state.ratings.add((liked: liked, words: _words(clean)));
        while (state.ratings.length > maxRatings) {
          state.ratings.removeAt(0);
        }
        final clipped = _clip(clean, maxReplyChars);
        state.liked.removeWhere((pair) => pair.reply == clipped);
        if (liked) {
          state.liked.add(NeuraLikedReply(
            prompt: _clip(prompt, maxPromptChars),
            reply: clipped,
            at: _now(),
          ));
          while (state.liked.length > maxLiked) {
            state.liked.removeAt(0);
          }
        }
        await _write(state);
      });

  /// Forgets every rating and liked reply.
  Future<void> forget() => _serial(() async {
        await NeuraPrefsCache.prefs.remove(storageKey);
      });

  Future<int> get likedCount async => (await _serial(_read)).liked.length;

  /// A short length preference learned from ratings, or ''.
  static String lengthHint(List<({bool liked, int words})> ratings) {
    if (ratings.length < 3) return '';
    final liked = ratings.where((r) => r.liked).map((r) => r.words).toList();
    final disliked =
        ratings.where((r) => !r.liked).map((r) => r.words).toList();
    double average(List<int> values) =>
        values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    final likedAverage = average(liked);
    final dislikedAverage = average(disliked);
    if (disliked.length >= 2 &&
        dislikedAverage > 80 &&
        (liked.isEmpty || likedAverage < dislikedAverage / 2)) {
      return 'They prefer short replies.';
    }
    if (liked.length >= 3 && likedAverage <= 45) {
      return 'They prefer short replies.';
    }
    if (liked.length >= 3 && likedAverage >= 120) {
      return 'They like fuller, more detailed replies.';
    }
    return '';
  }

  static Set<String> _keywords(String text) => RegExp(r"[a-z']{4,}")
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .toSet();

  /// The section for the on-device system prompt, or '' with nothing
  /// learned. Picks the liked exchanges closest to [newest] (word overlap),
  /// then the most recent, within [maxSectionBytes].
  Future<String> promptSection(String newest) async {
    final _StyleState state;
    try {
      // A plain read: it never waits behind a pending rating write, so a
      // reply is never held up by the queue.
      state = await _read();
    } catch (_) {
      return ''; // An unreadable style memory never blocks a reply.
    }
    return sectionFor(state.liked, state.ratings, newest);
  }

  @visibleForTesting
  static String sectionFor(
    List<NeuraLikedReply> liked,
    List<({bool liked, int words})> ratings,
    String newest,
  ) {
    final hint = lengthHint(ratings);
    if (liked.isEmpty) return hint;
    final words = _keywords(newest);
    final ranked = [...liked]..sort((a, b) {
        final overlap = _keywords(b.prompt).intersection(words).length -
            _keywords(a.prompt).intersection(words).length;
        return overlap != 0 ? overlap : b.at.compareTo(a.at);
      });
    final lines = <String>[_header];
    var bytes = utf8.encode(_header).length + utf8.encode(hint).length + 2;
    for (final pair in ranked.take(2)) {
      final line = '- They said: "${pair.prompt}" You replied: "${pair.reply}"';
      final size = utf8.encode(line).length + 1;
      if (bytes + size > maxSectionBytes) continue;
      lines.add(line);
      bytes += size;
    }
    if (lines.length == 1) return hint; // No example fit the budget.
    if (hint.isNotEmpty) lines.add(hint);
    return lines.join('\n');
  }
}

class _StyleState {
  final List<NeuraLikedReply> liked;
  final List<({bool liked, int words})> ratings;

  _StyleState(this.liked, this.ratings);
}
