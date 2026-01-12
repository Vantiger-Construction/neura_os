# Neura OS (Merged) — Install & Run

This bundle is the **fully merged Neura OS** with:
- Legacy Vault
- Neura Spaces (room routing)
- Focus + Ambient Rooms
- Voice Lab (offline WAV playback + live mic viseme driver)

## Quick start (Windows)
1. Install Flutter (SDK 3.x) and add it to PATH.
2. Open a terminal in `neura_os/`.
3. Run:
   - `scripts\Install-Neura-OS.bat`
   - or `powershell -ExecutionPolicy Bypass -File scripts\Install-Neura-OS.ps1`

## Audio assets
Voice samples are under:
`assets/audio/neura/`

## Voice Lab
Open **Rooms Map** → **Voice Lab**.
- Plays included WAV clips.
- Starts mic-driven viseme stream (for mouth animation inputs).

## Build APK
`powershell -ExecutionPolicy Bypass -File scripts\Install-Neura-OS.ps1 -BuildApk`

