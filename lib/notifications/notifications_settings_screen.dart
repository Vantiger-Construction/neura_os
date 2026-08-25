import 'package:flutter/material.dart';

import 'neura_notifications_prefs.dart';
import 'neura_notifications_service.dart';

class NotificationsSettingsScreen extends StatelessWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ValueListenableBuilder<NeuraNotificationsPrefs>(
        valueListenable: NeuraNotificationsPrefsController.instance.prefs,
        builder: (context, prefs, _) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Off by default. These use Windows toast notifications, so they can '
                  'reach you even when Neura isn\'t focused.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              SwitchListTile(
                value: prefs.weeklyReviewReadyEnabled,
                onChanged: (v) => NeuraNotificationsPrefsController.instance
                    .update(prefs.copyWith(weeklyReviewReadyEnabled: v)),
                secondary: const Icon(Icons.insights_outlined),
                title: const Text('Weekly review ready'),
                subtitle: const Text(
                    'A nudge once your weekly reflection has been drafted.'),
              ),
              SwitchListTile(
                value: prefs.legacyOverdueEnabled,
                onChanged: (v) => NeuraNotificationsPrefsController.instance
                    .update(prefs.copyWith(legacyOverdueEnabled: v)),
                secondary: const Icon(Icons.auto_stories_outlined),
                title: const Text('Legacy Guard check-in overdue'),
                subtitle: const Text(
                    'Only applies if Legacy Guard is enabled under Legacy Vault.'),
              ),
              SwitchListTile(
                value: prefs.dailyMoodNudgeEnabled,
                onChanged: (v) async {
                  final next = prefs.copyWith(dailyMoodNudgeEnabled: v);
                  await NeuraNotificationsPrefsController.instance.update(next);
                  if (v) {
                    await NeuraNotificationsService.instance
                        .scheduleDailyMoodNudge(
                      TimeOfDay(
                          hour: next.dailyMoodNudgeHour,
                          minute: next.dailyMoodNudgeMinute),
                    );
                  } else {
                    await NeuraNotificationsService.instance
                        .cancelDailyMoodNudge();
                  }
                },
                secondary: const Icon(Icons.favorite_outline),
                title: const Text('Daily mood check-in nudge'),
                subtitle: Text(
                  'Every day at ${TimeOfDay(hour: prefs.dailyMoodNudgeHour, minute: prefs.dailyMoodNudgeMinute).format(context)}.',
                ),
              ),
              if (prefs.dailyMoodNudgeEnabled)
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: const Text('Change reminder time'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: prefs.dailyMoodNudgeHour,
                        minute: prefs.dailyMoodNudgeMinute,
                      ),
                    );
                    if (picked == null) return;
                    final next = prefs.copyWith(
                      dailyMoodNudgeHour: picked.hour,
                      dailyMoodNudgeMinute: picked.minute,
                    );
                    await NeuraNotificationsPrefsController.instance
                        .update(next);
                    await NeuraNotificationsService.instance
                        .scheduleDailyMoodNudge(picked);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
