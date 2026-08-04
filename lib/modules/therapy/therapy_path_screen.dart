import 'package:flutter/material.dart';

import 'therapy_models.dart';
import 'therapy_prompt_card.dart';
import 'therapy_prompt_library.dart';
import 'therapy_reflection_screen.dart';

/// CBT / DBT / ACT reflection prompts - guided self-journaling drawn from
/// evidence-based therapeutic frameworks. This is a journaling tool, not
/// therapy or diagnosis; Neura does not claim to treat anything.
class TherapyPathScreen extends StatefulWidget {
  const TherapyPathScreen({super.key});

  @override
  State<TherapyPathScreen> createState() => _TherapyPathScreenState();
}

class _TherapyPathScreenState extends State<TherapyPathScreen> {
  String _selectedMethod = 'CBT';

  void _openPrompt(TherapyPrompt prompt) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TherapyReflectionScreen(prompt: prompt)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompts = TherapyPromptLibrary.forMethod(_selectedMethod);
    return Scaffold(
      appBar: AppBar(title: const Text('Therapy Journal')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: TherapyPromptLibrary.methods
                  .map((m) => ButtonSegment(value: m, label: Text(m)))
                  .toList(),
              selected: {_selectedMethod},
              onSelectionChanged: (s) => setState(() => _selectedMethod = s.first),
            ),
          ),
          Expanded(
            child: ListView(
              children: prompts.map((p) => TherapyPromptCard(prompt: p, onTap: () => _openPrompt(p))).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
