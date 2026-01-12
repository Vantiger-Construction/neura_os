import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/neura_voice_pack.dart';

class VoiceLabScreen extends StatefulWidget {
  const VoiceLabScreen({super.key});

  @override
  State<VoiceLabScreen> createState() => _VoiceLabScreenState();
}

class _VoiceLabScreenState extends State<VoiceLabScreen> {
  StreamSubscription? _sub;
  NeuraVisemeFrame _last = const NeuraVisemeFrame(
    talkLevel: 0,
    rest: 1,
    aa: 0,
    ee: 0,
    oo: 0,
    ff: 0,
    mm: 0,
    rms: 0,
    zcr: 0,
  );

  bool _micOn = false;

  @override
  void initState() {
    super.initState();
    _sub = NeuraVoicePack.I.visemes.listen((f) {
      setState(() => _last = f);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    try {
      if (!_micOn) {
        await NeuraVoicePack.I.startMic();
      } else {
        await NeuraVoicePack.I.stopMic();
      }
      setState(() => _micOn = !_micOn);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mic error: $e')),
      );
    }
  }

  Future<void> _play(String asset) async {
    try {
      await NeuraVoicePack.I.playAsset(asset);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Play error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _last.talkLevel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Voice Lab'),
        actions: [
          IconButton(
            tooltip: _micOn ? 'Stop mic' : 'Start mic',
            icon: Icon(_micOn ? Icons.mic_off : Icons.mic_none),
            onPressed: _toggleMic,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Offline voice + real-time visemes.\n'
            '• Playing a clip uses its viseme timeline if present (assets/audio/neura/visemes/<stem>.json).\n'
            '• Otherwise, Neura lip-syncs using your mic (if enabled).',
          ),
          const SizedBox(height: 16),
          _Bar(label: 'talkLevel', v: t),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: [
              _ChipBar(label: 'rest', v: _last.rest),
              _ChipBar(label: 'aa', v: _last.aa),
              _ChipBar(label: 'ee', v: _last.ee),
              _ChipBar(label: 'oo', v: _last.oo),
              _ChipBar(label: 'ff', v: _last.ff),
              _ChipBar(label: 'mm', v: _last.mm),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Sample clips:'),
          const SizedBox(height: 8),
          _Btn(
            label: 'Recording.wav',
            onTap: () => _play('assets/audio/neura/Recording.wav'),
          ),
          _Btn(
            label: 'Recording_upbeat.wav',
            onTap: () => _play('assets/audio/neura/Recording_upbeat.wav'),
          ),
          _Btn(
            label: 'to_tigger_vxxx1.wav',
            onTap: () => _play('assets/audio/neura/to_tigger_vxxx1.wav'),
          ),
          _Btn(
            label: 'to_tigger_vxxx2.wav',
            onTap: () => _play('assets/audio/neura/to_tigger_vxxx2.wav'),
          ),
          _Btn(
            label: 'to_tigger_vxxx3.wav',
            onTap: () => _play('assets/audio/neura/to_tigger_vxxx3.wav'),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow),
        label: Text(label),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double v;
  const _Bar({required this.label, required this.v});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${v.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: v.clamp(0, 1)),
      ],
    );
  }
}

class _ChipBar extends StatelessWidget {
  final String label;
  final double v;
  const _ChipBar({required this.label, required this.v});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ${v.toStringAsFixed(2)}', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: v.clamp(0, 1)),
        ],
      ),
    );
  }
}
