import 'package:flutter/material.dart';

import '../services/after_storm_service.dart';
import '../models/storm_event.dart';

class AfterStormScreen extends StatefulWidget {
  const AfterStormScreen({Key? key}) : super(key: key);

  @override
  State<AfterStormScreen> createState() => _AfterStormScreenState();
}

class _AfterStormScreenState extends State<AfterStormScreen> {
  final _service = AfterStormService.instance;

  String _intensity = 'medium';
  String _feeling = 'overwhelmed';
  bool _safetyRisk = false;
  final _whatHappenedController = TextEditingController();
  final _needNowController = TextEditingController();

  bool _saving = false;
  StormSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final summary = await _service.computeSummary(days: 7);
    if (!mounted) return;
    setState(() {
      _summary = summary;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final event = StormEvent(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        intensity: _intensity,
        primaryFeeling: _feeling,
        shortSummary: _whatHappenedController.text.trim(),
        needNow: _needNowController.text.trim(),
        safetyRisk: _safetyRisk,
        meta: {},
      );
      await _service.logEvent(event);
      await _loadSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Neura logged this storm. You made it through.'),
        ),
      );
      _whatHappenedController.clear();
      _needNowController.clear();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _whatHappenedController.dispose();
    _needNowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: Colors.indigo.shade900,
      appBar: AppBar(
        title: const Text('After the Storm'),
      },
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'That was a lot.\nLet's land together for a minute.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Step 1: Where are you at?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'How big did this storm feel?',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _intensityChip('mild', 'Shaken but okay'),
                          _intensityChip('medium', 'Really heavy'),
                          _intensityChip('severe', 'Huge storm'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'If you had to pick one word for the feeling:',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _feelingChip('angry'),
                          _feelingChip('sad'),
                          _feelingChip('scared'),
                          _feelingChip('numb'),
                          _feelingChip('overwhelmed'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            value: _safetyRisk,
                            onChanged: (v) {
                              setState(() {
                                _safetyRisk = v ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'This touched on safety / self-harm / danger.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Step 2: What happened?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'One or two sentences is enough. This is for future-you, not for a judge.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _whatHappenedController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Example: We argued and I felt blamed.',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Step 3: What do you need most right now?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You don't have to fix your whole life. Just one brick.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _needNowController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText:
                              'Example: water, quiet, message a safe person.',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : const Text('Log this storm with Neura'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (summary != null && summary.totalEvents > 0)
                Card(
                  color: Colors.black45,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last ${summary.days} days',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Storms logged: ${summary.totalEvents}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Most common intensity: ${summary.mostCommonIntensity}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'Most common feeling: ${summary.mostCommonFeeling}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (summary.safetyRiskEvents > 0)
                          Text(
                            'Safety-risk storms: ${summary.safetyRiskEvents}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intensityChip(String value, String label) {
    final selected = _intensity == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _intensity = value;
        });
      },
    );
  }

  Widget _feelingChip(String value) {
    final selected = _feeling == value;
    return ChoiceChip(
      label: Text(value),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _feeling = value;
        });
      },
    );
  }
}
