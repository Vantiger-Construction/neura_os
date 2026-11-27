import 'dart:async';

import 'package:flutter/material.dart';

import '../../avatar/motion/neura_body_cues.dart';
import '../../neura_shell/widgets/neura_penthouse_scene.dart';
import '../../services/emotion_analysis_service.dart';
import '../../services/neura_tts_service.dart';
import '../../startup/neura_prefs_cache.dart';

/// Body doubling: Neura quietly keeps you company while you do one task.
/// She checks in once at halfway and celebrates the finish. Only a count of
/// finished sessions is kept; the task name is never stored.
class NeuraFocusTogetherScreen extends StatefulWidget {
  const NeuraFocusTogetherScreen({super.key, this.speak});

  /// Says a short line aloud; defaults to Neura's voice when reply speech is
  /// on. Tests pass a recorder.
  final Future<void> Function(String text)? speak;

  static const minutesChoices = [15, 25, 45, 60];
  static const sessionsKey = 'neura.focus_together.sessions';

  @override
  State<NeuraFocusTogetherScreen> createState() =>
      _NeuraFocusTogetherScreenState();
}

class _NeuraFocusTogetherScreenState extends State<NeuraFocusTogetherScreen> {
  final _task = TextEditingController();
  int _minutes = 25;
  Duration _elapsed = Duration.zero;
  Duration? _total;
  Timer? _ticker;
  bool _paused = false;
  bool _halfwaySaid = false;
  bool _finished = false;
  String? _message;

  int get _sessions =>
      NeuraPrefsCache.prefsOrNull
          ?.getInt(NeuraFocusTogetherScreen.sessionsKey) ??
      0;

  @override
  void dispose() {
    _ticker?.cancel();
    _task.dispose();
    super.dispose();
  }

  Future<void> _say(String text) async {
    final speak = widget.speak;
    if (speak != null) return speak(text);
    final tts = NeuraTtsService.instance;
    if (tts.replySpeechMode == NeuraReplySpeechMode.off) return;
    await tts.speak(text).catchError((_) {});
  }

  void _start() {
    _ticker?.cancel();
    setState(() {
      _total = Duration(minutes: _minutes);
      _elapsed = Duration.zero;
      _paused = false;
      _halfwaySaid = false;
      _finished = false;
      _message = "I'm here. Let's begin.";
    });
    unawaited(_say("I'm here with you. Let's begin."));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final total = _total;
    if (total == null || _paused || _finished || !mounted) return;
    setState(() => _elapsed += const Duration(seconds: 1));
    if (!_halfwaySaid && _elapsed * 2 >= total) {
      _halfwaySaid = true;
      setState(() => _message = "Halfway there. How's it going?");
      unawaited(_say("Halfway there. You're doing it."));
    }
    if (_elapsed >= total) unawaited(_finish());
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    final count = _sessions + 1;
    setState(() {
      _finished = true;
      _message = 'You did it. That was focus time well spent.';
    });
    NeuraEmpathyMotion.respondTo(
      const EmotionRead(primary: 'joy', intensity: 0.9),
    );
    try {
      await NeuraPrefsCache.prefs
          .setInt(NeuraFocusTogetherScreen.sessionsKey, count);
    } catch (_) {}
    await _say('You did it. Well done.');
  }

  void _endEarly() {
    _ticker?.cancel();
    setState(() {
      _total = null;
      _message = null;
    });
  }

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    return Scaffold(
      appBar: AppBar(title: const Text('Focus together')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const NeuraPenthouseScene(dim: 0.55, showFurniture: false),
          SafeArea(
            child: total == null ? _setup(theme) : _running(theme, total),
          ),
        ],
      ),
    );
  }

  Widget _setup(ThemeData theme) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Pick one thing to do. I'll stay with you quietly, check in at "
            'halfway, and cheer when you finish.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('focus-task'),
            controller: _task,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'What are you working on? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final minutes in NeuraFocusTogetherScreen.minutesChoices)
              ChoiceChip(
                label: Text('$minutes min'),
                selected: _minutes == minutes,
                onSelected: (_) => setState(() => _minutes = minutes),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('focus-start'),
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start together'),
          ),
          if (_sessions > 0) ...[
            const SizedBox(height: 12),
            Text(
              _sessions == 1
                  ? 'One session finished together so far.'
                  : '$_sessions sessions finished together so far.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      );

  Widget _running(ThemeData theme, Duration total) {
    final remaining = total - _elapsed;
    final progress = (_elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    final task = _task.text.trim();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.isNotEmpty)
              Text(task,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(fit: StackFit.expand, children: [
                CircularProgressIndicator(value: progress, strokeWidth: 8),
                Center(
                  child: Text(
                    _finished ? 'Done' : _clock(remaining),
                    key: const Key('focus-clock'),
                    style: theme.textTheme.displaySmall,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            if (_message != null)
              Text(_message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            if (_finished)
              FilledButton(
                onPressed: _endEarly,
                child: const Text('Another one'),
              )
            else
              Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () => setState(() => _paused = !_paused),
                  child: Text(_paused ? 'Resume' : 'Pause'),
                ),
                OutlinedButton(
                  onPressed: _endEarly,
                  child: const Text('Stop'),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
