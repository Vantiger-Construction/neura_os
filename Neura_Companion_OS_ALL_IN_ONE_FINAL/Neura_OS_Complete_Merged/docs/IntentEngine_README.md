# Neura OS (Unified Skeleton)

This is a **modular, local-first** Neura OS skeleton.

## What’s included
- Unity ↔ Flutter bridge (Android channel + Windows TCP)
- Locomotion + prop interactions + cinematics scripts for Unity
- Emotion lighting / glow / breathing scripts
- Intent Engine + Intent Weaving
- **Encrypted local memory graph** (AES-GCM payload encryption + Drift/SQLite)

## Quick start (Flutter)
```bash
cd core
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

## Unity
Open `world/NeuraWorld` in Unity 2021 LTS+.

## Notes
This repo is a scaffold: it gives you the **wiring and modules**, ready to be integrated into your full Neura OS experience.
