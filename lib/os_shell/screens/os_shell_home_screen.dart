import 'package:flutter/material.dart';

import '../../mood/widgets/mood_adaptive_container.dart';
import '../../weekly/widgets/weekly_life_snapshot_card.dart';
import '../../dreams/screens/dream_theater_screen.dart';
import '../../care/screens/care_mode_home_screen.dart';
import '../../after_storm/screens/after_storm_screen.dart';
import '../../persona/screens/agent_persona_settings_screen.dart';
import '../../kids/screens/kids_mode_home_screen.dart';
import '../../mirror/screens/mirror_mode_screen.dart';
import '../../joy_engine/joy_engine.dart';
import '../../joy_engine/joy_screen.dart';
import '../../joy_engine/joy_types.dart';
import '../../mood/services/mood_state_service.dart';
import '../../relationships/screens/relationship_list_screen.dart';
import '../../relationships/screens/promises_list_screen.dart';
import '../widgets/neura_os_room_card.dart';

class OsShellHomeScreen extends StatelessWidget {
  const OsShellHomeScreen({super.key});

  static NeuraMood _mapMood(String raw) {
    switch (raw) {
      case 'anxious':
      case 'scared':
      case 'angry':
        return NeuraMood.stressed;
      case 'happy':
      case 'excited':
        return NeuraMood.energized;
      case 'sad':
        return NeuraMood.sad;
      case 'tired':
        return NeuraMood.tired;
      case 'calm':
        return NeuraMood.calm;
      default:
        return NeuraMood.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MoodAdaptiveContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Neura OS Shell'),
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          elevation: 0,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const WeeklyLifeSnapshotCard(),
                const SizedBox(height: 16),
                const Text(
                  'Rooms',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                NeuraOsRoomCard(
                  icon: Icons.self_improvement,
                  title: 'Reflection Bay',
                  subtitle: 'After the Storm + Weekly reflections.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AfterStormScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.favorite,
                  title: 'Care Wing',
                  subtitle: 'Care Mode, trusted contacts, safety plans.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CareModeHomeScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.nightlight_round,
                  title: 'Dream Theater',
                  subtitle: 'Dream Show 2.0 with recurring themes.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DreamTheaterScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.face_retouching_natural,
                  title: 'Mirror Mode',
                  subtitle: 'Set current mood and drive colors + difficulty.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MirrorModeScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.tune,
                  title: "Neura's Personas",
                  subtitle: 'Which specialist answers, and how Neura talks, jokes, and coaches you.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AgentPersonaSettingsScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.child_care,
                  title: 'Kids Corner',
                  subtitle: 'Kids-friendly Neura space (parents supervise).',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const KidsModeHomeScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.emoji_emotions_outlined,
                  title: 'Joy Lounge',
                  subtitle: 'A short, mood-aware Joy Moment. Always skippable.',
                  onTap: () async {
                    await MoodStateService.instance.load();
                    final mood = _mapMood(MoodStateService.instance.currentMood);
                    final moment = JoyEngine().pickMoment(mood);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NeuraJoyScreen(),
                        settings: RouteSettings(arguments: moment),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.people_alt_outlined,
                  title: 'Relationships',
                  subtitle: 'People, care scores, and interaction history.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RelationshipListScreen(),
                      ),
                    );
                  },
                ),
                NeuraOsRoomCard(
                  icon: Icons.checklist_rounded,
                  title: 'Promises',
                  subtitle: 'Things you said you\'d do, tracked gently.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PromisesListScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tip',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'You can swap this screen in as your main home / dashboard, '
                  'or route to it from your existing layout. It just ties all the '
                  'rooms together in one Neura OS shell.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
