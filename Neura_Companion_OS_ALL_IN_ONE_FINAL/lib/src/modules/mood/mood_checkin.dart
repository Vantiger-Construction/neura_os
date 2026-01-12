import 'package:flutter/material.dart';

class MoodCheckinScreen extends StatelessWidget {
  const MoodCheckinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mood Check-In')),
      body: const Center(child: Text('Track your mood & see emotional trends')),
    );
  }
}