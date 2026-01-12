import 'package:flutter/material.dart';

class ValuesCompassScreen extends StatefulWidget {
  const ValuesCompassScreen({super.key});

  @override
  State<ValuesCompassScreen> createState() => _ValuesCompassScreenState();
}

class _ValuesCompassScreenState extends State<ValuesCompassScreen> {
  final List<Map<String, dynamic>> _coreValues = [
    {
      'name': 'Integrity',
      'description': 'Being honest and having strong moral principles',
      'icon': Icons.verified,
      'color': Colors.blue,
      'selected': true,
    },
    {
      'name': 'Compassion',
      'description': 'Showing empathy and care for others',
      'icon': Icons.favorite,
      'color': Colors.red,
      'selected': true,
    },
    {
      'name': 'Growth',
      'description': 'Continuous learning and personal development',
      'icon': Icons.trending_up,
      'color': Colors.green,
      'selected': false,
    },
    {
      'name': 'Creativity',
      'description': 'Expressing imagination and innovation',
      'icon': Icons.brush,
      'color': Colors.purple,
      'selected': true,
    },
    {
      'name': 'Community',
      'description': 'Building connections and contributing to society',
      'icon': Icons.group,
      'color': Colors.orange,
      'selected': false,
    },
    {
      'name': 'Balance',
      'description': 'Maintaining harmony in all aspects of life',
      'icon': Icons.balance,
      'color': Colors.teal,
      'selected': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Values Compass'),
        backgroundColor: Colors.deepPurple,
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
                      'Your Values Compass',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Navigate your life by your core values. Select the values that guide your decisions.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _addNewValue,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Custom Value'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Core Values',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _coreValues.length,
                itemBuilder: (context, index) {
                  final value = _coreValues[index];
                  return _buildValueCard(value, index);
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
                      'Values Reflection',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'How well are you living according to your values? Take a moment to reflect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _startReflection,
                      child: const Text('Start Reflection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValueCard(Map<String, dynamic> value, int index) {
    return Card(
      elevation: value['selected'] ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: value['selected'] ? value['color'] : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => _toggleValue(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                value['icon'],
                size: 32,
                color: value['selected'] ? value['color'] : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                value['name'],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: value['selected'] ? value['color'] : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                value['description'],
                style: TextStyle(
                  fontSize: 12,
                  color: value['selected'] ? Colors.black87 : Colors.grey,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleValue(int index) {
    setState(() {
      _coreValues[index]['selected'] = !_coreValues[index]['selected'];
    });

    final value = _coreValues[index];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value['selected']
              ? ' added to your values'
              : ' removed from your values',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addNewValue() {
    // TODO: Implement add new value dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add custom value - Coming Soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _startReflection() {
    // TODO: Navigate to reflection screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Values reflection - Coming Soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
