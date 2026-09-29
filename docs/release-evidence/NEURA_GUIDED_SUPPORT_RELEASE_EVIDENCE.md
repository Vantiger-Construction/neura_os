# Help me through this — release evidence

**Prepared:** September 27, 2026  
**Feature baseline:** merged PR #108 at `3ae691156437f192d5d767e3fc645882ddcd8036`  
**Status:** automated regression evidence is defined; physical Windows and Android
evidence is **NOT COLLECTED**.

This record covers only the five release checks in
[`docs/NEURA_GUIDED_SUPPORT.md`](../NEURA_GUIDED_SUPPORT.md). It does not turn
guided support into treatment, prove clinical benefit, or replace the separate
content review and pilot proposal.

## Safety boundaries under test

- Activities and temporary writing remain local; no model, cloud, journal, sync,
  notification, or background-learning permission is granted.
- The only persisted record is encrypted, explicitly confirmed, and scoped to
  `suggest_in_guided_support`.
- Safe Mode keeps fixed manual activities available while blocking recall/save.
- Voice navigation stops capture before opening support and never resumes it on
  return.

## Reproducible automated evidence

| Release check | Automated coverage | What still requires a device |
|---|---|---|
| 1. Offline entry and activities | `guided_support_test.dart` opens Care Loop and Support Center entries, while `neura_voice_commands_test.dart` covers the Talk to Neura button. Every activity completes or exits without persistence. | Installed Windows and Android packages in an actual offline state. |
| 2. Windows voice aliases and mic-off return | `neura_voice_command_test.dart` accepts only the exact addressed phrases and rejects partial, quoted, and compound forms. The chat widget test uses the native speech channel seam, verifies stop-before-navigation for both aliases, and verifies mic-off after return. | A real Windows microphone and WinRT speech bridge; Android confirmation that buttons do not depend on that bridge. |
| 3. Remember/restart/replace/forget and unavailable credentials | `guided_support_test.dart` recreates the store, decrypts the scoped record, replaces it, copies only the four allowed fields, forgets it, and exercises unavailable credential reads with deletion still available. | Actual OS credential/key-store behavior across process restart on both platforms. |
| 4. Background, Safe Mode and data wipe | Widget/store tests clear drafts on lifecycle changes, invalidate an open confirmation, revoke an in-flight save when Safe Mode starts, drain/delete on wipe, and verify a fresh store cannot recreate the record. | Real app suspension/termination timing, Safe Mode transition, and full installed-app wipe. |
| 5. Accessibility, dark mode and narrow layout | Widget tests exercise 200% text at 320 × 640 in dark mode, run labeled-target and contrast guidelines, verify the skip control, and keep human support reachable. | Windows keyboard traversal and Narrator; Android TalkBack; platform text scaling and real narrow-window resizing. |

Focused reproduction:

```text
flutter test --no-pub --timeout 60s test/modules/support/guided_support_test.dart test/modules/chat/neura_voice_commands_test.dart test/services/neura_voice_command_test.dart
```

These files are also included by the existing
`tools/Neura-FastCheck.ps1` full `flutter test` invocation. No duplicate CI
test pass is added.

## Manual device evidence record

Use synthetic text such as `DEVICE TEST DRAFT`; never record private writing,
speech, clipboard contents, credentials, or recovery keys in screenshots or logs.

- Release candidate / build:
- Commit:
- Tester:
- Date:
- Windows device and OS:
- Android device and OS:
- How network access was disabled:
- Evidence folder or ticket:

| ID | Platforms | Procedure and pass condition | Status | Evidence reference |
|---|---|---|---|---|
| GS-1 | Windows + Android | Disable network access. From Talk to Neura, Care Loop, and Support Center, open the feature. Complete and separately exit Quiet writing, Grounding pause, and One small plan. No entry or activity may require network access or create a remembered preference without confirmation. | **NOT COLLECTED** | — |
| GS-2 | Windows; Android button only | With a real Windows microphone, try the primary phrase and both aliases. Verify partial, quoted, and compound speech do not navigate; valid speech stops capture before navigation; returning leaves the mic off. On Android, verify all three buttons work without the Windows speech bridge. | **NOT COLLECTED** | — |
| GS-3 | Windows + Android | Remember one activity, terminate and restart the app, inspect the explanation, copy the record, replace it with another activity, then forget it. Repeat with OS credentials unavailable; the error must remain visible and Forget must still remove the encrypted value. | **NOT COLLECTED** | — |
| GS-4 | Windows + Android | Enter synthetic writing, background the app, and verify it is gone on return. Background during confirmation, enter Safe Mode during a save, and perform full local-data wipe. No temporary writing or preference may return or be recreated. | **NOT COLLECTED** | — |
| GS-5 | Windows + Android | At 200% text in dark mode and the narrowest supported window, traverse every control with keyboard/Narrator on Windows and TalkBack on Android. Every prompt remains skippable and Reach a person remains discoverable and operable. | **NOT COLLECTED** | — |

## Release decision

Do not mark this evidence package complete until every manual row has a real build,
device/OS, tester, date, result, and evidence reference. A failed row blocks general
release until repaired and rerun. Cloud approval, local journaling, Safe Mode mic-off,
and no-background-cloud boundaries remain unchanged by this package.
