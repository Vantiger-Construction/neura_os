import 'package:flutter/material.dart';

class MoodReactiveShellScreen extends StatefulWidget {
  const MoodReactiveShellScreen({super.key});

  @override
  State<MoodReactiveShellScreen> createState() => _MoodReactiveShellScreenState();
}

class _MoodReactiveShellScreenState extends State<MoodReactiveShellScreen> {
  double _currentMood = 5.0; // Scale of 1-10
  String _selectedMood = 'Neutral';
  Color _moodColor = Colors.blue;
  String _moodMessage = 'How are you feeling today?';

  final List<Map<String, dynamic>> _moodOptions = [
    {'name': 'Very Low', 'value': 1.0, 'color': Colors.red, 'icon': Icons.sentiment_very_dissatisfied},
    {'name': 'Low', 'value': 3.0, 'color': Colors.orange, 'icon': Icons.sentiment_dissatisfied},
    {'name': 'Neutral', 'value': 5.0, 'color': Colors.blue, 'icon': Icons.sentiment_neutral},
    {'name': 'Good', 'value': 7.0, 'color': Colors.lightGreen, 'icon': Icons.sentiment_satisfied},
    {'name': 'Excellent', 'value': 9.0, 'color': Colors.green, 'icon': Icons.sentiment_very_satisfied},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mood Reactive Shell'),
        backgroundColor: _moodColor,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _moodColor.withOpacity(0.1),
              _moodColor.withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        _getCurrentMoodIcon(),
                        size: 64,
                        color: _moodColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _moodMessage,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Current Mood Level',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '/10',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _moodColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Slider(
                        value: _currentMood,
                        min: 1,
                        max: 10,
                        divisions: 9,
                        activeColor: _moodColor,
                        onChanged: (value) {
                          setState(() {
                            _currentMood = value;
                            _updateMoodState();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Quick Mood Check',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _moodOptions.length,
                itemBuilder: (context, index) {
                  final mood = _moodOptions[index];
                  return InkWell(
                    onTap: () => _selectMood(mood),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: mood['color'].withOpacity(
                          _selectedMood == mood['name'] ? 0.2 : 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedMood == mood['name']
                              ? mood['color']
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            mood['icon'],
                            color: mood['color'],
                            size: 24,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mood['name'],
                            style: TextStyle(
                              fontSize: 10,
                              color: mood['color'],
                              fontWeight: _selectedMood == mood['name']
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Mood-Based Recommendations',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ..._getMoodRecommendations().map((recommendation) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      recommendation['icon'],
                      color: _moodColor,
                    ),
                    title: Text(recommendation['title']),
                    subtitle: Text(recommendation['description']),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _executeRecommendation(recommendation),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Mood Journal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Track your mood patterns over time to better understand yourself.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _viewMoodHistory,
                        icon: const Icon(Icons.history),
                        label: const Text('View Mood History'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _moodColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCurrentMoodIcon() {
    if (_currentMood <= 2) return Icons.sentiment_very_dissatisfied;
    if (_currentMood <= 4) return Icons.sentiment_dissatisfied;
    if (_currentMood <= 6) return Icons.sentiment_neutral;
    if (_currentMood <= 8) return Icons.sentiment_satisfied;
    return Icons.sentiment_very_satisfied;
  }

  void _updateMoodState() {
    if (_currentMood <= 2) {
      _selectedMood = 'Very Low';
      _moodColor = Colors.red;
      _moodMessage = 'I\'m here for you. Let\'s focus on self-care.';
    } else if (_currentMood <= 4) {
      _selectedMood = 'Low';
      _moodColor = Colors.orange;
      _moodMessage = 'Things can get better. What small step can we take?';
    } else if (_currentMood <= 6) {
      _selectedMood = 'Neutral';
      _moodColor = Colors.blue;
      _moodMessage = 'A balanced day. How can we make it even better?';
    } else if (_currentMood <= 8) {
      _selectedMood = 'Good';
      _moodColor = Colors.lightGreen;
      _moodMessage = 'Great to see you feeling good! Let\'s build on this.';
    } else {
      _selectedMood = 'Excellent';
      _moodColor = Colors.green;
      _moodMessage = 'Outstanding! Let\'s celebrate and maintain this energy.';
    }
  }

  void _selectMood(Map<String, dynamic> mood) {
    setState(() {
      _selectedMood = mood['name'];
      _currentMood = mood['value'];
      _moodColor = mood['color'];
      _updateMoodState();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mood updated to '),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<Map<String, dynamic>> _getMoodRecommendations() {
    if (_currentMood <= 3) {
      return [
        {
          'icon': Icons.self_improvement,
          'title': 'Gentle Breathing Exercise',
          'description': 'A 2-minute breathing exercise to help you relax.',
        },
        {
          'icon': Icons.music_note,
          'title': 'Calming Music Playlist',
          'description': 'Soft, soothing music to help lift your spirits.',
        },
        {
          'icon': Icons.chat,
          'title': 'Talk to Someone',
          'description': 'Reach out to a friend or loved one for support.',
        },
      ];
    } else if (_currentMood <= 6) {
      return [
        {
          'icon': Icons.directions_walk,
          'title': 'Short Walk',
          'description': 'A 10-minute walk to clear your mind and boost energy.',
        },
        {
          'icon': Icons.book,
          'title': 'Read Something Inspiring',
          'description': 'Pick up a book or article that motivates you.',
        },
        {
          'icon': Icons.brush,
          'title': 'Creative Activity',
          'description': 'Try drawing, writing, or any creative outlet.',
        },
      ];
    } else {
      return [
        {
          'icon': Icons.celebration,
          'title': 'Celebrate Your Mood',
          'description': 'Take a moment to appreciate how you\'re feeling.',
        },
        {
          'icon': Icons.share,
          'title': 'Share the Positivity',
          'description': 'Spread good vibes to friends and family.',
        },
        {
          'icon': Icons.star,
          'title': 'Set New Goals',
          'description': 'Channel this positive energy into new achievements.',
        },
      ];
    }
  }

  void _executeRecommendation(Map<String, dynamic> recommendation) {
    // TODO: Implement recommendation execution
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting: '),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _viewMoodHistory() {
    // TODO: Navigate to mood history screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mood history - Coming Soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
