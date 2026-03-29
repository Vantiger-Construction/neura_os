import 'package:flutter/material.dart';

import '../models/mood_state.dart';
import '../services/mood_state_service.dart';
import '../services/mood_visual_service.dart';

/// A scaffold that automatically uses the current MoodState to drive
/// background gradient and accent color.
class MoodBackgroundScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;

  const MoodBackgroundScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final mood = MoodStateService.instance.currentMood;
    final style = MoodVisualService.instance.styleFor(_toMoodState(mood));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            style.backgroundTop,
            style.backgroundBottom,
          ],
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                secondary: style.accent,
                primary: style.accent,
              ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          floatingActionButton: floatingActionButton,
          body: body,
        ),
      ),
    );
  }

  MoodState _toMoodState(String mood) {
    final normalized = mood.toLowerCase();
    double score;
    switch (normalized) {
      case 'sad':
      case 'anxious':
      case 'angry':
        score = 2.5;
        break;
      case 'tired':
        score = 4.0;
        break;
      case 'calm':
      case 'neutral':
        score = 5.0;
        break;
      case 'happy':
        score = 7.5;
        break;
      case 'excited':
        score = 9.0;
        break;
      default:
        score = 5.0;
    }
    return MoodState(
      date: DateTime.now(),
      score: score,
      label: MoodLabel.neutral,
      note: '',
    );
  }
}
