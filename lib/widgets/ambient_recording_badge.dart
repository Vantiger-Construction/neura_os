import 'package:flutter/material.dart';

import '../services/ambient_listening_service.dart';
import '../src/modules/settings/settings.dart';

/// Small persistent "recording right now" badge, visible from every tab.
///
/// Only shows while [AmbientListeningService.isLive] is actually true (an
/// in-progress voice-activity-triggered capture) -- never merely because
/// the mic stream is open and waiting for the next utterance. Tapping it
/// jumps straight to Settings, where the pause toggle lives.
class AmbientRecordingBadge extends StatelessWidget {
  const AmbientRecordingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AmbientListeningService.instance.isLive,
      builder: (context, isLive, _) {
        if (!isLive) return const SizedBox.shrink();
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 6),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record,
                            color: Colors.white, size: 12),
                        SizedBox(width: 6),
                        Text(
                          'Recording',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
