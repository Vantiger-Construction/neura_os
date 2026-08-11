import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String _kFeedbackEmail = 'stevenvantiger1@gmail.com';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _buildBody(String feedback) {
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    return '$feedback\n\n---\nSent from the Neura beta feedback form\nPlatform: $os ($osVersion)';
  }

  Future<void> _send() async {
    final feedback = _controller.text.trim();
    if (feedback.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a bit of feedback first.')),
      );
      return;
    }

    setState(() => _sending = true);
    final uri = Uri(
      scheme: 'mailto',
      path: _kFeedbackEmail,
      queryParameters: {
        'subject': 'Neura Beta Feedback',
        'body': _buildBody(feedback),
      },
    );

    try {
      final launched = await launchUrl(uri);
      if (!launched) throw Exception('launchUrl returned false');
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Couldn\'t open a mail app. Email your feedback directly to $_kFeedbackEmail.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Feedback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Found a bug, or something feel off? Let us know below — this '
              'opens your mail app with your feedback pre-filled, addressed '
              'to the Neura team.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'What happened? What did you expect instead?',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send_outlined),
              label: Text(_sending ? 'Opening mail app…' : 'Send Feedback'),
            ),
          ],
        ),
      ),
    );
  }
}
