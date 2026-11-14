# Wellbeing preview and user controls

The wellbeing home keeps three starting choices: settle, take a small step,
or reach someone. Its additional links expose comfort controls, suggestion
choices, appointment preparation and voluntary usability feedback.

## Isolated Windows preview

Use the repository-pinned Flutter toolchain and its existing locked dependencies:

```powershell
flutter run -d windows --debug --no-pub --dart-define=NEURA_DEMO=true
```

The preview opens maximized and supports Flutter hot reload (`r`). Hot restart
(`R`) resets the sample session. Closing it discards its in-memory check-ins,
suggestion choices, comfort settings and demo clipboard. Use fictional text.

This is a separate native host, selected by CMake from the same generated
`DART_DEFINES` as the Dart entrypoint. Duplicate or malformed `NEURA_DEMO`
definitions fail configuration. The target does not link/register production
plugins, Rust engines, speech services or the diagnostic vault. Dart requires
the `neura/isolated_preview` host handshake before displaying the sample app;
missing, failed or timed-out verification shows an unavailable screen and does
not enter production startup. Normal builds retain the production target.

The preview reuses the real support, timer, check-in, history, appointment,
feedback and comfort widgets through explicit in-memory ports. Its persistent
banner identifies sample data. Journals and trusted-contact records lead to an
unavailable screen. Profiles, backup, restore, wipe, voice, models, cloud and the
floating companion are not exposed. Copy buttons use an in-memory preview
clipboard; normal text-field selection menus are provided by Flutter/Windows.
Those standard menus are not a private clipboard, so use synthetic text only.

This is a safe editing surface, not proof that production persistence, hardware,
installation, recovery or clinical outcomes work. A successful build is also
not proof of a successful interactive run. Record those results separately.

## Comfort and navigation

Explicit text scaling now supports 85–200%, preserving the operating system's
text scaler (including nonlinear scaling). The combined scaler is bounded at
400%. OS high contrast and reduced motion remain respected. Low-stimulation
mode also requests reduced motion. Support routes accept Escape to go back,
and forms are scrollable with labelled controls at large text sizes.

Production comfort choices retain their existing persistence. Preview comfort
choices use a session-local notifier and do not initialize the real preference
controller. Test automation covers semantics and layout; assistive-technology
and lived-experience testing still need real participants.

## Guided-support suggestion choices

These choices affect only the remembered activity offered in guided support.
They do not control chat, reminders or other recommendation systems. Users can
require an explicit **Show suggested activity** request and exclude individual
activities from suggestions. Excluded activities remain manually available.

Opening choices is explicit. Editing does not save them. A separate confirmation
authorizes the displayed choices only; edits, backgrounding, route cover, Safe
Mode and recovery revoke it. Saving uses the existing device encryption and
admission queue under `neura.guidedSupport.choices.v1`. No journal text, mood
history, feedback or inferred trait is stored there. The strict versioned schema
rejects malformed content. Corrupt ciphertext is not treated as plaintext.

**Forget suggestion choices** removes this record and verifies absence while
leaving the separately remembered activity unchanged. Full data wipe suspends
admission, drains pending writes and removes both records. As with the existing
store, an unconfirmed deletion is an error, not a successful wipe.

## Appointment preparation

Opening this screen does not read history. **Choose saved check-ins** explicitly
loads available check-ins and offers the latest thirty valid, non-future entries.
None are preselected; at most ten can be included. Notes are excluded by default.
Optional note excerpts are bounded to 500 Unicode code points and visibly marked
when shortened. Missing energy/sleep values are omitted, not rendered as zero.

The user can add questions, review an editable summary, remove any text and
explicitly confirm copying that exact draft. Editing revokes confirmation.
Production copying uses the OS clipboard and does not contact a clinic or send
anything. Clipboard contents may outlive the screen; Neura does not erase the
user's clipboard. There is no automatic export, PDF upload or clinical inference.

Stop, leaving the route/app, Safe Mode changes and recovery clear the temporary
draft and invalidate delayed results. Reopening does not resume it. The summary
labels scores as self-reports, not diagnosis or evidence of treatment benefit.

## Voluntary feedback

The optional form asks about finding support, stopping, understanding storage
and finding human support. Every answer may be skipped. It requests no symptom
assessment or identifiers and has no analytics or automatic submission. Free text
can still contain sensitive information: users are asked to leave it out and can
edit the complete report before explicitly copying it. Nothing is persisted.

See [the review protocol](WELLBEING_USABILITY_REVIEW.md) for the human evaluation
that remains necessary. Shipping a form does not mean that review has happened.

## Relevant checks

Use the pinned SDK, cached dependencies and bounded concurrency:

```powershell
flutter test --no-pub --concurrency 1 --timeout 2m test/preview/neura_demo_test.dart test/modules/support/private_support_forms_test.dart test/modules/support/support_choices_and_summary_test.dart test/modules/support/support_suggestion_screen_test.dart test/modules/support/support_suggestion_store_test.dart
python -m unittest discover -s tools/tests -p test_neura_preview_mode.py -v
flutter analyze --no-pub --fatal-infos
flutter build windows --debug --no-pub
flutter build windows --debug --no-pub --dart-define=NEURA_DEMO=true
```

The Python checks use an already installed CMake (`NEURA_TEST_CMAKE` may name its
path) and retain tiny synthetic fixtures. No SDK installation is part of these
checks. Validate both native targets and preserve exact source/build identities.
