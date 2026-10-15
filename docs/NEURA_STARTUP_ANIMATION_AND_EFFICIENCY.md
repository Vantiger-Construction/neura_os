# Startup animation and avatar efficiency

Neura's packaged full-body artwork now appears in both the early bootstrap
frame and the service-startup screen. A small breathing/floating transform
animates the existing image; it is not a new skeletal Unity animation or a
speaking greeting. The startup widget does not start a microphone, speech,
model, avatar-runtime, or cloud service.

## Efficiency changes

- `AvatarView` retains its asset-resolution future through parent, size and
  controller updates. A changed primary path, format, fallback path or idle
  variant creates a new resolution attempt. Each attempt captures its own spec,
  and an older completion cannot replace a newly selected avatar.
- The startup image is outside the animation-frame builder and has its own
  repaint boundary. Only small transforms change on each animation frame.
  Image decode height is bounded at 1024 physical pixels; both startup surfaces
  use the same default size so Flutter can reuse the decoded image.
- Startup motion has one owned ticker. Reduced motion, a disabled `TickerMode`,
  Safe Mode, a paused boot attempt, and background lifecycle states stop motion.
  Leaving startup disposes its ticker and lifecycle observer.
- The first bootstrap frame paints before optional window-role initialization;
  the boot screen paints before the coordinator starts. Readiness navigates on
  the next requested frame instead of waiting a fixed 350 ms, and the normal
  route fade is reduced from 600 ms to 200 ms. Reduced motion uses no fade.
- Existing sign-in, device-lock, Safe Mode and recovery routing is retained.
  Routing gates are read when navigation executes, not before a delayed callback.

These are reductions in redundant work and intentional UI delay. They are not
a measured promise about total boot time, CPU usage, voice latency or LLM speed.
No service ordering, consent boundary, native audio warmup, background cloud
policy, journaling authority or encrypted-memory contract is changed.

## Validation

The State Matrix runs the two focused suites before full-project analysis:

```powershell
flutter test --reporter expanded --timeout 60s `
  test/startup/neura_startup_avatar_test.dart `
  test/avatar/avatar_view_cache_test.dart
```

The suites check bounded image use across animation frames, reduced motion,
covered routes, foreground/background transitions, disposal, missing artwork,
reused asset probes, fallback resolution and late completions after selection.
The existing full-project analysis and startup/recovery/Safe Mode tests remain
required; the new focused step does not waive those checks.

At implementation time, draft PR #128 separately repairs chat compilation on
the default branch. This startup change does not copy or alter that branch's
work. An exact-head CI failure in that existing chat code must be distinguished
from a failure in these focused suites. Rebase after the compile repair lands
and retain fresh validation evidence before release.

## Physical-device acceptance

Use the same device and package configuration to collect before/after cold and
warm startup timings, preferably at least five launches of each. Record time
to first frame and usable dashboard, peak memory and idle CPU. The coordinator's
existing sanitized module-duration diagnostics help identify remaining delays.

Check Neura is visible during startup on Windows and Android, does not delay
dashboard readiness, stops moving on background/hidden/inactive states, resumes
only in the foreground and stops after startup. Test Safe Mode, reduced motion,
missing artwork, failed startup and retry, cached-ready re-entry, sign-in and
device-lock routing, small windows and enlarged text. Native speech and physical
Engine lifecycle acceptance remain separate release gates.
