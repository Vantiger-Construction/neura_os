import 'package:flutter/material.dart';

class SessionEngineScreen extends StatelessWidget {
  const SessionEngineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Engine'),
        backgroundColor: Colors.indigo,
      ),
      body: const Center(
        child: Text('Session Engine - Coming Soon!'),
      ),
    );
  }
}
