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
      _loading = false;
    });
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
          ],
        ),
      ),
    );
  }
}
