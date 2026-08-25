import 'package:flutter/material.dart';

import '../human/human_prefs_controller.dart';
import '../mood/mood_models.dart';
import 'coach_engine.dart';
import 'coach_models.dart';
import 'coach_popup.dart';
import 'coach_store.dart';

class CoachHooks {
  CoachHooks._();

  static Future<void> afterMoodCheckin(
      BuildContext context, MoodEntry entry) async {
    final prefs = HumanPrefsController.instance.prefs.value;
    if (!prefs.coachEnabled) return;

    final draft = NeuraCoachEngine.instance.forMoodCheckin(entry: entry);
    final note = await CoachStore.instance.add(
      source: CoachSourceType.moodCheckin,
      title: draft.title,
      body: draft.body,
      tags: draft.tags,
    );

    if (!context.mounted) return;
    if (prefs.coachPopups) {
      await CoachPopup.show(context, note);
    }
  }

  static Future<void> afterRescueCompleted(BuildContext context,
      {MoodEntry? latestMood}) async {
    final prefs = HumanPrefsController.instance.prefs.value;
    if (!prefs.coachEnabled) return;

    final draft =
        NeuraCoachEngine.instance.forRescueCompleted(latestMood: latestMood);
    final note = await CoachStore.instance.add(
      source: CoachSourceType.rescue,
      title: draft.title,
      body: draft.body,
      tags: draft.tags,
    );

    if (!context.mounted) return;
    if (prefs.coachPopups) {
      await CoachPopup.show(context, note);
    }
  }

  static Future<void> afterRescueHelpful(
    BuildContext context, {
    required String actionId,
    MoodEntry? latestMood,
  }) async {
    final prefs = HumanPrefsController.instance.prefs.value;
    if (!prefs.coachEnabled) return;

    final draft = NeuraCoachEngine.instance
        .forRescueHelpful(actionId: actionId, latestMood: latestMood);
    await CoachStore.instance.add(
      source: CoachSourceType.rescue,
      title: draft.title,
      body: draft.body,
      tags: draft.tags,
    );
  }
}
