import 'package:flutter/material.dart';

import '../models/neura_audience.dart';
import '../services/neura_audience_service.dart';

class AudienceSettingsScreen extends StatefulWidget {
  const AudienceSettingsScreen({super.key});

  @override
  State<AudienceSettingsScreen> createState() => _AudienceSettingsScreenState();
}

class _AudienceSettingsScreenState extends State<AudienceSettingsScreen> {
  final _service = NeuraAudienceService.instance;
  bool _loading = true;
  NeuraAudience _audience = NeuraAudience.adult;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.load();
    if (!mounted) return;
    setState(() {
      _audience = _service.currentAudience;
      _loading = false;
    });
  }

  Future<void> _updateAudience(NeuraAudience value) async {
    setState(() {
      _audience = value;
    });
    await _service.setAudience(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audience preference updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Audience & Safety'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Who is Neura mainly talking to on this device?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This helps Neura choose safer language, depth, and difficulty. '
                    'You can still have specific modes (like Kids Corner) override this '
                    'when needed.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<NeuraAudience>(
                    segments: const [
                      ButtonSegment(
                        value: NeuraAudience.adult,
                        label: Text('Adult'),
                      ),
                      ButtonSegment(
                        value: NeuraAudience.teen,
                        label: Text('Teen'),
                      ),
                      ButtonSegment(
                        value: NeuraAudience.child,
                        label: Text('Child'),
                      ),
                    ],
                    selected: <NeuraAudience>{_audience},
                    onSelectionChanged: (selection) {
                      _updateAudience(selection.first);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Adult: full depth. Teen: clear, supportive language. Child: very gentle mode.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Important: Neura is not a doctor or therapist. '
                    'For medical, mental health, or safety emergencies, '
                    'contact real-world professionals and emergency services.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
    );
  }
}
