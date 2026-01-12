import 'package:flutter/material.dart';

class FocusModeScreen extends StatefulWidget {
  const FocusModeScreen({super.key});

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  bool _isFocusModeActive = false;
  int _focusDuration = 25; // minutes
  int _breakDuration = 5; // minutes

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Mode'),
        backgroundColor: _isFocusModeActive ? Colors.red : Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Focus Mode',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isFocusModeActive
                          ? 'Focus mode is active. Stay productive!'
                          : 'Enable focus mode to block distractions and stay productive.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _toggleFocusMode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFocusModeActive ? Colors.red : Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: Text(
                        _isFocusModeActive ? 'End Focus Session' : 'Start Focus Session',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Session Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Focus Duration (minutes):'),
                        DropdownButton<int>(
                          value: _focusDuration,
                          items: [15, 25, 45, 60].map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text(' min'),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _focusDuration = newValue;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Break Duration (minutes):'),
                        DropdownButton<int>(
                          value: _breakDuration,
                          items: [5, 10, 15, 20].map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text(' min'),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _breakDuration = newValue;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Focus Tips',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: const [
                  ListTile(
                    leading: Icon(Icons.lightbulb),
                    title: Text('Find a quiet workspace'),
                    subtitle: Text('Minimize distractions in your environment.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.phone_android),
                    title: Text('Put your phone on silent'),
                    subtitle: Text('Disable notifications during focus sessions.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.task),
                    title: Text('Break tasks into smaller chunks'),
                    subtitle: Text('Use the Pomodoro technique for better focus.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.water_drop),
                    title: Text('Stay hydrated'),
                    subtitle: Text('Keep water nearby and take regular breaks.'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleFocusMode() {
    setState(() {
      _isFocusModeActive = !_isFocusModeActive;
    });

    if (_isFocusModeActive) {
      // TODO: Implement focus mode activation
      // - Block notifications
      // - Set do not disturb
      // - Start timer
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Focus mode activated for  minutes'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // TODO: Implement focus mode deactivation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Focus mode deactivated'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
