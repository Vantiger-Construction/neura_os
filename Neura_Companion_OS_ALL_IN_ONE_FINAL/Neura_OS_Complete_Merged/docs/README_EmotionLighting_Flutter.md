# Flutter side (Emotion/Lighting)

You already send `SET_STATE` with `mood` and `energy`.
This patch adds an optional `NeuraStateModel` helper.

Example:

```dart
bridge.send(NeuraStateModel(mood: "anxious", energy: 0.42, room: "MoodDen").toJson());
```

Unity will now *show* mood (glow/breathing/lighting/posture), not just store it.
