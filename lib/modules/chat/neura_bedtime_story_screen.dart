import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/neura_ai_service.dart';
import '../../services/neura_tts_service.dart';
import '../../services/neura_voice_tone.dart';
import '../../widgets/neura_cloud_request_preview.dart';

/// Bedtime stories: Neura makes up a gentle story and reads it in her
/// slowest, softest voice, with a sleep timer. Nothing is saved.
class NeuraBedtimeStoryScreen extends StatefulWidget {
  const NeuraBedtimeStoryScreen({
    super.key,
    required this.localOllama,
    this.aiService,
    this.ttsService,
  });

  final bool localOllama;
  final NeuraAiService? aiService;
  final NeuraTtsService? ttsService;

  static const themes = <String, String>{
    'Forest': 'a quiet forest at dusk, with soft moss and a slow stream',
    'Sea': 'a calm sea at night, a small boat and gentle waves',
    'Stars': 'a hill under the stars, drifting clouds and a warm blanket',
    'Cabin': 'a cozy cabin in the snow, a crackling fire and warm tea',
    'Garden': 'a moonlit garden, sleepy flowers and fireflies',
  };

  static const timers = <int>[0, 10, 20, 30];

  static const system = 'You tell gentle bedtime stories for adults who want '
      'to fall asleep. About 250 words, in short, calm paragraphs separated '
      'by blank lines. Slow, soothing and kind: soft sounds, warm light, '
      'nothing frightening, sad or exciting, no cliffhangers and no '
      'questions to the listener. Second person or a gentle narrator. End '
      'with everything settling into rest. Reply with only the story.';

  static String request(String theme, String include) {
    final extra = include.trim();
    return 'Please tell me a bedtime story set in $theme.'
        '${extra.isEmpty ? '' : ' Include: $extra.'}';
  }

  /// The story as spoken chunks: paragraphs, with any long paragraph split
  /// at sentences, so no single utterance runs long.
  static List<String> chunks(String story, {int maxChars = 600}) {
    final out = <String>[];
    for (final paragraph in story.split(RegExp(r'\n\s*\n'))) {
      final text = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      if (text.length <= maxChars) {
        out.add(text);
        continue;
      }
      var current = '';
      for (final sentence in RegExp(r'[^.!?]+[.!?]*\s*').allMatches(text)) {
        final s = sentence.group(0)!;
        if (current.isNotEmpty && current.length + s.length > maxChars) {
          out.add(current.trim());
          current = '';
        }
        current += s;
      }
      if (current.trim().isNotEmpty) out.add(current.trim());
    }
    return out;
  }

  @override
  State<NeuraBedtimeStoryScreen> createState() =>
      _NeuraBedtimeStoryScreenState();
}

class _NeuraBedtimeStoryScreenState extends State<NeuraBedtimeStoryScreen> {
  final _include = TextEditingController();
  String _theme = NeuraBedtimeStoryScreen.themes.keys.first;
  int _sleepMinutes = 20;
  String? _story;
  bool _writing = false;
  bool _reading = false;
  int _readGeneration = 0;
  Timer? _sleepTimer;

  NeuraAiService get _ai => widget.aiService ?? NeuraAiService.instance;
  NeuraTtsService get _tts => widget.ttsService ?? NeuraTtsService.instance;

  @override
  void dispose() {
    _stopReading();
    _tts.useTone(NeuraVoiceTone.neutral);
    _include.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    if (_writing) return;
    _stopReading();
    setState(() {
      _writing = true;
      _story = null;
    });
    try {
      final turn = await _ai.rehearsalTurn(
        system: NeuraBedtimeStoryScreen.system,
        messages: [
          {
            'role': 'user',
            'content': NeuraBedtimeStoryScreen.request(
              NeuraBedtimeStoryScreen.themes[_theme]!,
              _include.text,
            ),
          },
        ],
        localOllama: widget.localOllama,
        requestCloudApproval: (preview) => mounted
            ? showNeuraCloudRequestPreview(context, preview)
            : Future.value(false),
      );
      if (!mounted) return;
      setState(() => _story = turn.text);
      if (!turn.blocked) unawaited(_read());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.localOllama
              ? 'A story is unavailable. Check that Ollama is open.'
              : 'A story is unavailable right now.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _read() async {
    final story = _story;
    if (story == null) return;
    final generation = ++_readGeneration;
    _sleepTimer?.cancel();
    if (_sleepMinutes > 0) {
      _sleepTimer = Timer(Duration(minutes: _sleepMinutes), _stopReading);
    }
    _tts.useTone(NeuraVoiceTone.bedtime);
    setState(() => _reading = true);
    for (final chunk in NeuraBedtimeStoryScreen.chunks(story)) {
      if (generation != _readGeneration || !mounted) return;
      try {
        await _tts.speak(chunk);
      } catch (_) {
        break;
      }
      // A breath between paragraphs.
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    if (generation == _readGeneration && mounted) {
      setState(() => _reading = false);
    }
  }

  void _stopReading() {
    _readGeneration++;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    unawaited(_tts.stop().catchError((_) {}));
    if (mounted && _reading) setState(() => _reading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bedtime story')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Where should tonight\'s story go?',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final name in NeuraBedtimeStoryScreen.themes.keys)
                ChoiceChip(
                  label: Text(name),
                  selected: _theme == name,
                  onSelected: (_) => setState(() => _theme = name),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const Key('bedtime-include'),
              controller: _include,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Include something? (optional)',
                hintText: 'An old dog, rain on the roof…',
                border: OutlineInputBorder(),
              ),
            ),
            Row(children: [
              const Text('Stop reading after'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _sleepMinutes,
                items: [
                  for (final minutes in NeuraBedtimeStoryScreen.timers)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(minutes == 0 ? 'the end' : '$minutes min'),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _sleepMinutes = value ?? 0),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('bedtime-tell'),
              onPressed: _writing ? null : _write,
              icon: const Icon(Icons.nights_stay_outlined),
              label: Text(_story == null ? 'Tell me a story' : 'Another story'),
            ),
            if (_writing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_story != null) ...[
              const SizedBox(height: 16),
              Row(children: [
                if (_reading)
                  OutlinedButton.icon(
                    onPressed: _stopReading,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop reading'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _read,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: const Text('Read it to me'),
                  ),
              ]),
              const SizedBox(height: 12),
              SelectableText(
                _story!,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
