import 'package:flutter/material.dart';

class AutomationHubScreen extends StatefulWidget {
  const AutomationHubScreen({super.key});

  @override
  State<AutomationHubScreen> createState() => _AutomationHubScreenState();
}

class _AutomationHubScreenState extends State<AutomationHubScreen> {
  final List<Map<String, dynamic>> _automations = [
    {
      'name': 'Morning Routine',
      'description': 'Wake up, check weather, play music',
      'isActive': true,
      'icon': Icons.wb_sunny,
    },
    {
      'name': 'Evening Wind Down',
      'description': 'Dim lights, play calming music, set alarm',
      'isActive': false,
      'icon': Icons.nightlight_round,
    },
    {
      'name': 'Work Start',
      'description': 'Open work apps, set focus mode, start timer',
      'isActive': true,
      'icon': Icons.work,
    },
    {
      'name': 'Exercise Reminder',
      'description': 'Daily exercise notification at 6 PM',
      'isActive': false,
      'icon': Icons.fitness_center,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automation Hub'),
        backgroundColor: Colors.purple,
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
                      'Smart Automation',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Automate your daily routines and workflows to make life easier.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _createNewAutomation,
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Automation'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your Automations',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _automations.length,
                itemBuilder: (context, index) {
                  final automation = _automations[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: automation['isActive'] ? Colors.green : Colors.grey,
                        child: Icon(
                          automation['icon'],
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        automation['name'],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: automation['isActive'] ? Colors.black : Colors.grey,
                        ),
                      ),
                      subtitle: Text(automation['description']),
                      trailing: Switch(
                        value: automation['isActive'],
                        onChanged: (bool value) {
                          setState(() {
                            _automations[index]['isActive'] = value;
                          });
                          _showAutomationToggleSnackBar(automation['name'], value);
                        },
                      ),
                      onTap: () => _editAutomation(index),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildQuickActionButton(
                          icon: Icons.alarm,
                          label: 'Set Timer',
                          onPressed: _setTimer,
                        ),
                        _buildQuickActionButton(
                          icon: Icons.music_note,
                          label: 'Play Music',
                          onPressed: _playMusic,
                        ),
                        _buildQuickActionButton(
                          icon: Icons.lightbulb,
                          label: 'Smart Lights',
                          onPressed: _controlLights,
                        ),
                        _buildQuickActionButton(
                          icon: Icons.thermostat,
                          label: 'Climate',
                          onPressed: _controlClimate,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewAutomation,
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
          ),
          child: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _createNewAutomation() {
    // TODO: Navigate to automation creation screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Automation creation - Coming Soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _editAutomation(int index) {
    // TODO: Navigate to automation editing screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Editing: '),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAutomationToggleSnackBar(String name, bool isActive) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isActive ? ' automation activated' : ' automation deactivated',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _setTimer() {
    // TODO: Implement timer setting
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Timer feature - Coming Soon!')),
    );
  }

  void _playMusic() {
    // TODO: Implement music playback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Music playback - Coming Soon!')),
    );
  }

  void _controlLights() {
    // TODO: Implement smart lights control
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Smart lights - Coming Soon!')),
    );
  }

  void _controlClimate() {
    // TODO: Implement climate control
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Climate control - Coming Soon!')),
    );
  }
}
