import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates & Upgrades'),
      ),
      body: UpgradeAlert(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Neura OS Updates',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Updates are checked automatically when you open the app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'This screen ensures your Neura Companion stays up to date.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
