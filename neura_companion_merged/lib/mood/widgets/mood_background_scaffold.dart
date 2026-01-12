import 'package:flutter/material.dart';

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
    final mood = MoodStateService.instance.current;
    final style = MoodVisualService.instance.styleFor(mood);

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
}
