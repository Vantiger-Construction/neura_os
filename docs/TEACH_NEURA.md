# Teach Neura: explicit delivery preferences

This first slice lets the ordinary installation owner choose answer detail
(Brief, Balanced, Detailed) and starter plan size (one or three steps). It does
not infer preferences from conversation, enable reflection, retrain a model, or
change memory, microphone, cloud, action or profile permissions.

## Use

- Open **Teach Neura** from **Your Neura**, **Chat options**, or **Plan my day**.
- Select an option and review the exact proposal before choosing **Just today**,
  **Save preference**, or **No**. Selecting an option alone changes nothing.
- The screen shows saved and currently effective values separately. Remove each
  preference independently to restore its existing default.
- Answer detail shapes future replies through the existing prompt builder.
  The current user request can ask for a different level of detail. Model
  adherence is not guaranteed; the existing safety charter remains intact.
- Plan size changes only **Suggest starter steps**. It does not truncate
  templates, rewrite an existing plan, approve a plan or execute its tasks.

## Lifetime and data

**Just today** is deliberately temporary: it lives in RAM until local midnight,
backgrounding, Safe Mode, recovery, profile activation, or process exit. It does
not survive a restart. Saved choices are unchanged when a temporary choice ends.

Saved preferences contain only two optional enum values and a schema version.
They are encrypted with AES-GCM under the verified OS-backed installation key.
There is no transcript, journal, goal, free-form personal fact, remote identifier
or automatic collection in this store. These are explicit delivery settings,
not admitted companion notes or a substitute for a memory consent lease.
The selected answer style can shape an already-authorized model request; it
does not itself submit a local or cloud request. Cloud submission retains its
fresh exact-request approval.

The feature is unavailable in local profile mode. Those workspaces still do
not establish independent human ownership, and new profile setup remains paused.
No profile learns from or inherits the ordinary installation's teaching settings.

## Failure and cancellation

An edit is bound to one direct gesture, the loaded revision, the current session
generation and a five-minute deadline. Navigation covering the teaching screen,
disposal, backgrounding, Safe Mode and recovery revoke pending edits. Duplicate
writes are refused. Writes are acknowledged only after platform persistence and
readback verification. An unconfirmed outcome clears the active cache and
requires durable review before a new edit. It is never silently retried.

An OS write already submitted cannot be retracted by closing the screen. If it
finishes after cancellation, no success is reported and its value is used only
after a fresh load. Full local-data wipe closes admission synchronously and
drains admitted preference/key operations before removing their destinations.
A drain timeout reports incomplete deletion and keeps admission closed.

## Validation

Use the branch's pinned Flutter version and lockfile:

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub test/teaching test/planning test/persona test/profiles
flutter analyze --fatal-infos
flutter test --no-pub --concurrency 2 --timeout 2m
python3 tools/test_avatar_source_composition.py
python3 -m unittest discover -s tools/security -p 'test_*.py' -v
git diff --check
```

Synthetic tests cover explicit choices, temporary expiry, revisions, ambiguous
storage, real AES envelopes, key revocation, interruption, route coverage,
late completion, wipe drainage, prompt bounds and planner integration. No real
user content, microphone, cloud model or OS profile is a fixture.

Run installed-device acceptance separately: on an isolated Windows test account,
save and reopen preferences, restart, exercise temporary lifetime and interrupted
edits, verify a useful local reply with each detail level, and test the starter
plan choices at large text size. Do not overwrite a valuable installation or
weaken the existing 8 GB target's model admission/context limits. Android needs
its own installed-device evidence. CI or widget fixtures alone do not establish
model quality, hardware performance or public-release readiness.
