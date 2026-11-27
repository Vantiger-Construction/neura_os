import 'package:flutter/material.dart';

import '../services/wellbeing_check_service.dart';

/// The monthly wellbeing check: five questions about the last two weeks,
/// then the score and how it has moved. Everything stays on this device.
class WellbeingCheckScreen extends StatefulWidget {
  const WellbeingCheckScreen({super.key, this.service});

  /// Defaults to [WellbeingCheckService.instance]; tests pass their own.
  final WellbeingCheckService? service;

  @override
  State<WellbeingCheckScreen> createState() => _WellbeingCheckScreenState();
}

class _WellbeingCheckScreenState extends State<WellbeingCheckScreen> {
  late final WellbeingCheckService _service =
      widget.service ?? WellbeingCheckService.instance;
  final List<int?> _answers =
      List<int?>.filled(WellbeingCheckService.questions.length, null);
  List<WellbeingCheckResult> _history = const [];
  bool _loading = true;
  bool _saving = false;
  bool _answering = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<WellbeingCheckResult> history = const [];
    var due = true;
    String? error;
    try {
      history = await _service.history();
      due = await _service.isDue();
    } catch (_) {
      error = 'Past checks could not be read on this device.';
    }
    if (!mounted) return;
    setState(() {
      _history = history;
      _answering = due || history.isEmpty;
      _error = error;
      _loading = false;
    });
  }

  bool get _complete => _answers.every((answer) => answer != null);

  Future<void> _save() async {
    if (!_complete || _saving) return;
    setState(() => _saving = true);
    String? error;
    try {
      await _service.record([for (final answer in _answers) answer!]);
    } catch (_) {
      error = 'The check could not be saved on this device.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    setState(() {
      _saving = false;
      _loading = true;
    });
    await _load();
    if (!mounted) return;
    setState(() => _answering = false);
  }

  static String _bandText(WellbeingBand band) {
    switch (band) {
      case WellbeingBand.good:
        return 'In the range most people report.';
      case WellbeingBand.reduced:
        return 'Lower than people usually report. Worth noticing, and worth '
            'being gentle with yourself.';
      case WellbeingBand.low:
        return 'This has been a hard stretch. Talking with someone you trust '
            'or a doctor can really help.';
    }
  }

  static String _changeText(int change) {
    if (change == 0) return 'The same as last time.';
    if (change > 0) return 'Up $change since last time.';
    return 'Down ${-change} since last time.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.available) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wellbeing check')),
        body: const Center(
          child: Text('The wellbeing check is not available here.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Wellbeing check')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_answering) ..._questions(context) else _results(context),
              ],
            ),
    );
  }

  List<Widget> _questions(BuildContext context) {
    final theme = Theme.of(context);
    const choices = WellbeingCheckService.choices;
    return [
      Text(
        'Over the last two weeks…',
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        'Five questions from the WHO-5 Well-Being Index. Your answers stay '
        'on this device.',
        style: theme.textTheme.bodySmall,
      ),
      for (var i = 0; i < WellbeingCheckService.questions.length; i++) ...[
        const SizedBox(height: 16),
        Text(
          WellbeingCheckService.questions[i],
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var score = 0; score < choices.length; score++)
              ChoiceChip(
                key: ValueKey<String>('wellbeing-$i-$score'),
                label: Text(choices[score]),
                selected: _answers[i] == score,
                onSelected: (_) => setState(() => _answers[i] = score),
              ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _complete && !_saving ? _save : null,
        child: Text(_saving ? 'Saving…' : 'See my score'),
      ),
    ];
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _history.last;
    final previous =
        _history.length >= 2 ? _history[_history.length - 2] : null;
    final change = previous == null ? null : latest.percent - previous.percent;
    final localizations = MaterialLocalizations.of(context);
    final nextCheck = latest.takenAt.add(WellbeingCheckService.interval);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${latest.percent} / 100', style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(_bandText(WellbeingBand.of(latest.percent))),
        if (change != null) ...[
          const SizedBox(height: 8),
          Text(_changeText(change)),
        ],
        const SizedBox(height: 16),
        Text(
          'Next check from ${localizations.formatMediumDate(nextCheck)}.',
          style: theme.textTheme.bodySmall,
        ),
        if (_history.length > 1) ...[
          const SizedBox(height: 24),
          Text('Past checks', style: theme.textTheme.titleMedium),
          for (final result in _history.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${result.percent} / 100'),
              subtitle: Text(localizations.formatMediumDate(result.takenAt)),
            ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() {
            for (var i = 0; i < _answers.length; i++) {
              _answers[i] = null;
            }
            _answering = true;
          }),
          child: const Text('Take it again'),
        ),
      ],
    );
  }
}
