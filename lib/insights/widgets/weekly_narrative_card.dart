import 'package:flutter/material.dart';

import '../services/weekly_summarist_service.dart';

/// A short LLM-drafted narrative summary of the week, self-loading like
/// [WeeklyLifeSnapshotCard]. Shows a brief inline loader only in its own
/// slot while pending (never blocks the rest of the screen); renders
/// nothing -- no error text -- on any failure, missing API key, or
/// guardrail block, matching neura_chat_screen.dart's "degrade silently to
/// the existing local experience" philosophy.
class WeeklyNarrativeCard extends StatefulWidget {
  const WeeklyNarrativeCard({super.key});

  @override
  State<WeeklyNarrativeCard> createState() => _WeeklyNarrativeCardState();
}

class _WeeklyNarrativeCardState extends State<WeeklyNarrativeCard> {
  final _service = WeeklySummaristService.instance;

  bool _loading = true;
  String? _text;
  WeeklyNarrativeCorrection? _correction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    var state = await _service.currentIfFresh();
    if (state == null) {
      // Covers the race where this screen opens before app-open's
      // background generation has finished -- awaits the same memoized
      // future rather than starting a second call.
      await _service.maybeGenerateOnAppOpen();
      state = await _service.currentIfFresh();
    }

    if (!mounted) return;
    setState(() {
      _text = state?.summaryText;
      _correction = _service.pendingCorrection;
      _loading = false;
    });
  }

  /// "Not quite right?": the user picks what was off, and next week's draft
  /// follows fixed guidance for it. Their own words never reach the model.
  Future<void> _correct() async {
    final picked = await showModalBottomSheet<WeeklyNarrativeCorrection>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('What was off about this week’s words?'),
              subtitle: Text('Your feedback will be kept for a future draft.'),
            ),
            for (final option in WeeklyNarrativeCorrection.values)
              ListTile(
                title: Text(option.label),
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var message = 'Thanks. Your feedback is saved for a future draft.';
    try {
      await _service.recordCorrection(picked);
    } catch (_) {
      message = 'That could not be saved on this device.';
    }
    if (!mounted) return;
    setState(() => _correction = _service.pendingCorrection);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 20,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final text = _text;
    if (text == null) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.deepPurple.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_view_week_outlined,
                    color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text(
                  'This Week, In Words',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: Colors.white)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _correct,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: Text(
                  _correction == null
                      ? 'Not quite right?'
                      : 'Saved feedback: ${_correction!.label}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
