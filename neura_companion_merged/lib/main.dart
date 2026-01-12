import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';
import 'dreams/screens/dream_show_screen.dart';
import 'care/screens/care_mode_home_screen.dart';
import 'mirror/screens/mirror_mode_screen.dart';
import 'kids/screens/kids_mode_home_screen.dart';
import 'persona/screens/audience_settings_screen.dart';
import 'os_shell/screens/os_shell_home_screen.dart';
import 'insights/screens/weekly_snapshot_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return UpgradeAlert(
      child: MaterialApp(
        title: 'Neura Companion Merged',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Companion'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Dream Show'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DreamShowScreen())),
          ),
          ListTile(
            title: const Text('Care Mode'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CareModeHomeScreen())),
          ),
          ListTile(
            title: const Text('Mirror Mode'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MirrorModeScreen())),
          ),
          ListTile(
            title: const Text('Kids Mode'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KidsModeHomeScreen())),
          ),
          ListTile(
            title: const Text('Audience Settings'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudienceSettingsScreen())),
          ),
          ListTile(
            title: const Text('OS Shell'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OsShellHomeScreen())),
          ),
          ListTile(
            title: const Text('Weekly Snapshot'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklySnapshotScreen())),
          ),
        ],
      ),
    );
  }
}
