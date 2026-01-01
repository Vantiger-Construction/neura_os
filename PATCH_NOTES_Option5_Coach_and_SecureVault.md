# Neura OS – Option 5 Patch (Coach + Secure Vault)

This patch adds **Neura Coach** (local reflections after actions) and upgrades the **Memory Vault** from XOR-obfuscation to **AES‑GCM encryption** (key derived from your PIN via PBKDF2).

## What’s new

### 1) Neura Coach
- **Coach Timeline**: Neura writes short reflections after:
  - **Quest completed today**
  - **Weekly Review generated**
- **Settings**: enable/disable Coach, and enable/disable pop‑up reflections.
- **Export**: copy coach timeline as JSON to clipboard.

Where to find it:
- Dashboard tile: **Neura Coach**
- Settings: **Neura Coach**
- Rooms: Tools → **Neura Coach**

### 2) Memory Vault – AES‑GCM encryption
- Vault items are stored using **AES‑GCM**.
- Key is derived from your PIN using PBKDF2 (HMAC‑SHA256).
- Automatically migrates legacy vault blobs (v1) to the new format (v2) the first time you open it.

Notes:
- The current UI still stores the PIN in SharedPreferences (convenience). A “prompt every time + keystore” upgrade is planned.

## Files added
- `lib/modules/coach/*`

## Files updated
- `lib/modules/quests/quest_mode_screen.dart` (adds coach hook after completion)
- `lib/modules/review/weekly_review_screen.dart` (adds coach hook after generation)
- `lib/src/modules/settings/settings.dart` (adds Neura Coach tile)
- `lib/src/shell/rooms_catalog.dart` (adds Neura Coach room)
- `lib/modules/navigation/enhanced_navigation.dart` (adds dashboard tile)
- `lib/modules/human/human_prefs.dart` (adds coachEnabled/coachPopups)
- `lib/modules/vault/memory_vault_store.dart` (AES‑GCM encryption + migration)
- `lib/modules/vault/memory_vault_screen.dart` (updated messaging)
