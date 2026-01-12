import 'package:flutter/material.dart';
import '../services/journal_prompt_service.dart';

class JournalPromptScreen extends StatefulWidget {
  @override
  _JournalPromptScreenState createState() => _JournalPromptScreenState();
}

class _JournalPromptScreenState extends State<JournalPromptScreen> {
  final _service = JournalPromptService();
  String _prompt = '';

  void _loadPrompt() async {
    final p = await _service.fetchPrompt(time: DateTime.now());
    setState(() => _prompt = p);
  }

  @override
  void initState() {
    super.initState();
    _loadPrompt();
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Journal Prompt')),
      body: Center(child: Text(_prompt)),
    );
  }
}
