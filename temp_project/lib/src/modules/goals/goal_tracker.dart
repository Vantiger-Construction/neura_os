import 'package:flutter/material.dart';

class GoalTrackerScreen extends StatelessWidget {
  const GoalTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Goal Tracker')),
      body: const Center(child: Text('Daily/Weekly Goals & Streaks')),
    );
  }
}