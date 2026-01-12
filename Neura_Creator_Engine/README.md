# Neura Creator Engine (Drop-in Module)

Adds memory-aware, guardrail-safe content creation to Neura OS.

## What you get
- Content types: Ritual, MiniLesson, ReflectionPrompt, MicroQuest, JoyMoment
- Personalization from recent memory signals (mood/intent/outcomes)
- Guardrails first: optional, short, non-coercive, throttled
- Outcome hooks: log offered/accepted/declined so Neura learns ethically

## Install
Copy the folder:
- `core/lib/creator_engine/` into your Flutter project `core/lib/creator_engine/`

## Wire-up (example)
```dart
final engine = NeuraCreatorEngine(
  memory: memoryGraphService,
  guardrails: guardrails,
);

final item = await engine.generate();
if (item != null) {
  Navigator.pushNamed(context, '/creator', arguments: item);
}
```

## Routes
- Add route: `/creator` -> `NeuraCreatorScreen`

## Notes
- This module is local-first and works offline.
- It does not call external APIs by default. You can plug an LLM later via the `ContentBackend` interface.
