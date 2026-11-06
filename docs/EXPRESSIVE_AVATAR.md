# Expressive face in the app

**Settings → Choose Avatar → Neura expressive face** now selects a built-in
portrait in the normal Neura Stage and room presence panel. The choice is saved
on this device and restored during startup. The default remains the original
full-body artwork. Selecting an avatar never starts speech, capture or a model.

The selector previously created a separate `AvatarService`, so its selection
could miss the live room's notifier. It now uses the shared instance, and boot
loads that same instance. A failed save retains the previous selection and
shows an error. Unknown stored IDs fall back to Neura. The registry is the single
catalog for rendering and selection.

## What actually moves

The new `flutterFace` renderer uses the mouth-free vector portrait and
`NeuraMouthLayer` already exercised by the speech prototype. It requires no
external Rive file, asset download or new plugin. Normal speech events reach the
same global controller used by the room. On Windows, mouth shapes come from the
existing local SAPI visemes; other speech providers retain their existing event
behavior and are not claimed to have native phoneme timing.

The shared body runtime also applies the saved personality to this portrait's
breathing, sway and aura. Mouth movement requires that runtime to be live. Still,
recovery, Safe Mode and background stop it; the mouth layer additionally enforces
route tickers and accessibility reduced motion. Returning to an active renderer
requires a fresh speech onset rather than replaying a cached open mouth. Selecting
the face during an utterance therefore leaves it at rest until the next one.

This is a simple 2D portrait, not a fully rigged version of the painted character.
The Rive renderer remains a fallback. The separate floating Windows mascot keeps
its original artwork and existing body motion. Safe Mode's room illustration
also retains its existing static artwork. Automatic personality learning and
separate profiles for people sharing one installation are not added here.

## Try the build

1. Close any older Neura window and mascot before opening the preview.
2. Choose **Settings → Choose Avatar → Neura expressive face**, then return to
   the main app. The stage/presence panel should change immediately.
3. Keep companion motion at **Subtle** or **Expressive**. In **Your Neura**, save
   Calm companion or Playful spark to compare the existing personal body motion.
4. Use **Choose Avatar → Try local speech** for the fixed Windows speech sample.
   To check the main stage, return to ordinary chat and use an already configured
   speech-enabled reply. Local generated replies still require the selected
   Ollama provider, running local server and installed model. The speech sample
   is fixed text and does not demonstrate model intelligence.
5. Interrupt a reply, minimize/restore, enable Still or Safe Mode, and start a
   fresh permitted reply. Check for closed lips while stopped and no stale
   reopening. Restart the app to check that the selected face returns.
6. Select **Neura** to return to the original artwork.

## Evidence and limits

`avatar_selection_test.dart` checks persistence, unknown IDs, rejected and pending
saves, reset invalidation, live room selection and Still/recovery boundaries.
`flutter_mouth_sapi_test.dart` drives the real Dart speech adapter, event bridge,
controller and normal `AvatarView` with synthetic native-channel responses. Its
existing pixel/golden, cancellation and lifecycle tests still apply to the reused
mouth layer. These are implementation tests, not recordings of Windows audio.

Full Flutter and platform CI must be read on the exact published head. An
installer and successful build alone do not establish audible synchronization,
GUI launch, conversation quality or resource use on the user's laptop. The
package's `--launch-smoke-test` sentinel exits before Flutter initialization.
Record actual device results separately.
