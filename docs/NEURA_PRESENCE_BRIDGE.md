# Neura presence bridge

The presence bridge lets the Unity presence prototype
(`prototypes/unity-presence`) follow Neura's live avatar state: room, phase
(idle, listening, thinking, speaking, Safe Mode), stance, motion and scale. It
carries only the content-free presentation snapshot
(`NeuraAvatarRuntimeSnapshot.toJson()`, schema in
`prototypes/unity-presence/Contract/avatar-presence-v2.schema.json`). No
conversation, memory, journal or credential data crosses it.

The app publishes **v2**, which adds Neura's own room (`her_suite`) and three
display-only stage fields: `lighting` (`standard`, `gold`, `aurora`, `dusk`),
`camera` (`follow`, `wide`, `face`) and `activity` (`present`, `resting`). The
relay and the Unity receiver still accept **v1** (the original seven fields,
which can't name `her_suite`), so an older app build keeps working. Each
version must carry exactly its own fields. Safe Mode forces Still motion and,
in v2, the present pose. An older Unity build that only knows v1 rejects v2
and stays in safe Still, so update Unity and the app together.

It is **off by default**. Nothing connects unless Neura is started through
the trusted launcher.

## How it fits together

```
Neura app ──presence_publish──▶ neura_api presence relay ──avatar_presence──▶ Unity prototype
 (publisher)    (loopback, bearer token)    (latest snapshot only)    (loopback, same token)
```

| Piece | Where | Role |
| --- | --- | --- |
| Launcher | `tools/Start-NeuraPresenceBridge.ps1` | Generates a fresh session token, starts `neura_api` with `NEURA_API_PRESENCE_RELAY=1`, then starts Unity and the app with the relay address and token in their child environment only. Revokes the session and stops every child when Neura exits. |
| Relay | `rust/src/presence_relay.rs`, wired in `rust/src/bin/neura_api.rs` | One publisher slot, any number of subscribers (within the existing 4-client limit). Validates every snapshot strictly and keeps only the latest. |
| Publisher | `lib/avatar/presence_relay/` | Started from the navigation shell only when the launcher variables are present. Publishes on every change and every 2 s. |
| Subscriber | `prototypes/unity-presence/Assets/Presence/Bridge/` | `Protocol` (pure C#: config, envelope reader, relay client) and `Live` (the `PresenceLiveBridge` component, attached at runtime only when launched). |

## Her Suite: Unity stage, Flutter panels

Her Suite (`lib/her_suite/`) splits the work. The Flutter screens (the suite,
Sit together, Her shelf and Resting) draw frosted glass panels over a stage
slot. Today the slot shows the Flutter avatar. Once Unity takes over, pass a
`HerSuiteStageBuilder` that hosts the Unity window; nothing else changes.

The panels change only the display-only stage values (`lighting`, `camera`,
`activity`) through `HerSuiteStageController`, which calls
`NeuraAvatarRuntimeBridge.updateStage`. Those enum names are all that reach
Unity. Chat, memories and settings stay in Flutter: Her shelf shows taught
settings as labels and links to the screens that own them, never memory or
conversation content. Safe Mode refuses resting and ends a rest at once.
Visiting the suite switches the shell's room to `her_suite`, and leaving
switches it back.

## Authorization

- The relay is part of `neura_api` and uses its existing session check:
  numeric loopback peer only, no `Origin` header, constant-time
  `Authorization: Bearer <64-hex token>`, revocable through
  `POST /session/revoke`. Revocation closes every relay connection.
- The token exists only in the launcher's memory and its children's
  environment. It is never written to disk, the registry, the command line,
  logs, `toString()` output or saved preferences.
- Both clients accept only a numeric loopback address (`127.x.y.z:port` or
  `[::1]:port`), so no DNS lookup can send the token elsewhere.
- Roles are fixed per connection: the first presence message makes it the
  publisher or a subscriber. There is one publisher at a time; a second gets
  `presence publisher already active`.

## Freshness and fail-closed behavior

| Event | Result in Unity |
| --- | --- |
| Valid snapshot | Shown (Safe Mode canonicalized to Safe Mode + Still on both ends) |
| Unchanged heartbeat | Coalesced at the relay; re-sent every 2 s as a keepalive and not re-applied, so motion continues smoothly |
| Publisher silent for 6 s | `avatar_presence_cleared` (stale) → safe Still |
| Publisher disconnects, clears, or the app is hidden/paused | `avatar_presence_cleared` → safe Still |
| Invalid snapshot (unknown/private field, bad value, wrong version) | Publisher gets an error that never echoes input; presence withdrawn → safe Still |
| No frame for 8 s, connection drop, or reconnect | Unity resets to safe Still and reconnects with backoff (1–30 s) |
| Unity loses focus or pauses | Prototype suspends as before; on return the bridge asks the relay to resend the current state |

The relay stores no history. Each subscriber's delivery rules live in
`SubscriberView`, which is unit tested without sockets.

## Running it

```powershell
cargo build --release --manifest-path rust/Cargo.toml --bin neura_api
flutter build windows
# Unity player build:
pwsh tools/Start-NeuraPresenceBridge.ps1 -UnityExecutable 'C:\Builds\NeuraPresence\NeuraPresence.exe'
# Or the Unity Editor (press Play once it opens):
pwsh tools/Start-NeuraPresenceBridge.ps1 `
  -UnityExecutable 'C:\Program Files\Unity\Hub\Editor\6000.6.6f1\Editor\Unity.exe' `
  -UnityArguments '-projectPath', (Resolve-Path prototypes\unity-presence)
```

The Unity stage shows a status line at the bottom right: `connecting`,
`waiting for Neura`, `live` or `reconnecting`.

## Verification

| Check | Command | Status |
| --- | --- | --- |
| Relay unit and socket tests (13) | `cargo test --manifest-path rust/Cargo.toml --bin neura_api presence` | Passing |
| Unity core + bridge scenarios (22 + 9) | `bash prototypes/unity-presence/Tools/run_core_tests.sh` | Passing (Mono) |
| Contract and bridge isolation audit | `python3 prototypes/unity-presence/Tools/verify_contract.py` | Passing |
| Real relay ↔ Unity relay client end-to-end | `bash prototypes/unity-presence/Tools/run_bridge_e2e.sh` | Passing (Mono + real `neura_api`) |
| Dart publisher tests | `flutter test test/avatar/neura_presence_relay_test.dart` | Runs in CI |
| Unity Editor/player, Windows launcher run | Manual, see the prototype README | **Not yet executed** |

The `Neura presence bridge` workflow runs the first four plus a launcher parse
check on pull requests.
