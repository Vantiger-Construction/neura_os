import 'package:flutter/material.dart';

import '../services/mood_state_service.dart';
import '../services/mood_theme_service.dart';

class MoodAdaptiveContainer extends StatefulWidget {
  final Widget child;

  const MoodAdaptiveContainer({Key? key, required this.child})
      : super(key: key);

  @override
  State<MoodAdaptiveContainer> createState() =>
      _MoodAdaptiveContainerState();
}

class _MoodAdaptiveContainerState extends State<MoodAdaptiveContainer> {
  final _state = MoodStateService.instance;
  final _themes = MoodThemeService.instance;

  String _mood = 'neutral';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _state.load();
    if (!mounted) return;
    setState(() {
      _mood = _state.currentMood;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes.themeFor(_mood);

    return Container(
      decoration: BoxDecoration(gradient: theme.background),
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                secondary: theme.accent,
                primary: theme.accent,
              ),
        ),
        child: widget.child,
      ),
    );
  }
}
