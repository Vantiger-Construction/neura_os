import 'package:flutter/material.dart';

import '../dashboard/dashboard.dart';
import '../goals/goal_tracker.dart';
import '../journal/journal.dart';
import '../meditation/meditation.dart';
import '../mood/mood_checkin.dart';
import '../settings/settings.dart';
import '../legacy/legacy_deadman_service.dart';

class EnhancedNavigation extends StatefulWidget {
  const EnhancedNavigation({super.key});

  @override
  State<EnhancedNavigation> createState() => _EnhancedNavigationState();
}

class _EnhancedNavigationState extends State<EnhancedNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    DashboardScreen(),
    JournalScreen(),
    MoodCheckinScreen(),
    GoalTrackerScreen(),
    MeditationScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LegacyDeadmanService.instance.maybePromptOnStartup(context);
    });
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Journal'),
          BottomNavigationBarItem(icon: Icon(Icons.mood), label: 'Check-In'),
          BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'Goals'),
          BottomNavigationBarItem(icon: Icon(Icons.spa), label: 'Meditation'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
