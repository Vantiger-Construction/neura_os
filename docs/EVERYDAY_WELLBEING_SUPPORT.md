# Everyday wellbeing support

The home screen offers three explicit choices: settle, take one small step, and
reach someone. This is everyday support for adults, without diagnosis, treatment
recommendations, symptom inference, emergency monitoring or claims of clinical
effectiveness. It does not activate profiles, microphones, audio, cloud providers,
models, clinic contact or companion-memory ingestion.

## User controls and storage

- Grounding, optional gentle breathing and quiet writing reuse guided support.
  Every activity is optional and can be stopped. Breathing has no forced pace or
  breath holds. Remembering an activity still requires the existing confirmation;
  drafts and optional feedback are not saved.
  Guided support also clears temporary writing when another screen covers it.
  Backgrounding, navigation and safety/recovery changes expire open preference
  requests and remove their displayed private content. Returning requires an
  explicit Show remembered activity action; an expired approval cannot be reused.
  Recovery blocks preference reads and new saves before encryption is accessed,
  while manual exercises and explicitly requested forgetting remain available.
- The small-step timer runs only after a tap, for five minutes, without sound.
  Rest and enjoyable activities are valid choices. The user can stop at any time.
  Its countdown uses elapsed time, so changing the device clock cannot make it
  jump forward or backward.
  Pause keeps the remaining time and current writing in this screen. Resume
  requires another tap and uses only that remaining time. Pausing schedules no
  timer completion; leaving, Stop and clear, or a safety/recovery transition
  cancels even a paused session. Returning never resumes it automatically.
  Repeated Start requests cannot reset an active or paused timer. An initially
  inactive screen waits for a new foreground Start action.
  Suggested steps fill an empty draft directly. Replacing custom writing requires
  Use suggestion; Keep my step leaves it intact. Editing or leaving invalidates
  pending replacement choices, including an older choice with the same text.
- Routine reminders are **session-only**, silent and opt-in. They do not schedule
  OS/background notifications. Leaving the route/app, a safety transition or
  disposal cancels them; returning does not restart them. Quiet hours use the
  device's local clock and are checked on start, while running and on completion.
  Equal start/end hours mean quiet all day. Routine choices/settings are not saved.
- Human-support drafts have a 2,000-character limit, stay in memory, and clear on
  leaving the screen/app or a safety transition. Copy is an explicit action with
  a clipboard disclosure. Nothing is sent. Already-copied text remains outside
  Neura on the system clipboard. Appointment notes do not bypass the clinic hold.
  Templates leave existing writing intact until the user confirms replacement.
  Editing or leaving invalidates a pending replacement. A late clipboard result
  cannot label newer writing as copied.
- Clearing temporary human-support, small-step, guided-writing or check-in text
  also replaces the editor's Undo history. Undo/Redo cannot restore that cleared
  writing. This is logical removal, not a claim of physical memory zeroization.
- Crisis contacts are bundled text, available offline, with manual location
  selection. Locale is not treated as proof of location. There is no automatic
  calling, texting, browsing, location lookup or contact-store access.
  Inline country choices preserve a draft while changing the displayed contacts.
- Saved writing opens the existing local journal only after the user's choice;
  its explicit-save and separate companion-memory controls remain intact.
- Check-ins reuse the encrypted mood store and its wipe/write-drain protections.
  Energy and sleep are nullable, optional metadata. Old entries are unchanged;
  missing/invalid optional metadata is omitted, never interpreted as zero.
  The seven-day summary reports means of recorded entries with sample counts,
  excludes future entries, and makes no diagnosis or causal claim. Repeated
  check-ins are not presented as independent daily measurements.
  Leaving or covering history, or a safety transition, hides its cached content
  and invalidates pending reads. Returning requires an explicit Show saved history
  action. Hide history is also available manually; neither action deletes entries.

No dependency, lockfile, backend, notification permission or clinical profile
change is required. Existing privacy, wipe, provider-consent and clinic holds
remain in force. The home card only creates widgets; personal stores are not
opened until a person chooses the corresponding screen.

## Content sources

Original UI wording is informed by these public sources, checked 14 November
2026. Crisis details need periodic human review; a bundled number is not a live
availability guarantee.

- [WHO: Doing What Matters in Times of Stress](https://www.who.int/publications/i/item/9789240003927)
- [NHS: Tackling your to-do list](https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/self-help-cbt-techniques/tackling-your-to-do-list/)
- [NHS: Breathing exercises for stress](https://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/)
- [NIMH: Caring for your mental health](https://www.nimh.nih.gov/health/topics/caring-for-your-mental-health)
- [US 988](https://988lifeline.org/contact-us/)
- [Canada 9-8-8](https://988.ca/get-help/help-right-now)
- [Samaritans phone support, UK and Ireland](https://www.samaritans.org/how-we-can-help/contact-samaritan/talk-us-phone/)
- [NHS emergency services](https://www.nhs.uk/nhs-services/urgent-and-emergency-care-services/when-to-call-999/)
- [Ireland emergency services](https://www2.hse.ie/emergencies/when-to-call-112-or-999/)

## Validation scope

Synthetic widget/model tests cover entry navigation, narrow layout and enlarged
text, explicit start/stop, completion, route/background/safety cancellation,
quiet hours, manual country choice, clipboard consent, draft clearing, optional
check-in values, backward compatibility, summary denominators and failure/late
completion handling. Existing guided-support and navigation tests remain part of
the focused regression run.

Follow-up regressions also cover template replacement consent and revocation,
clock changes, late clipboard results, hidden history and stale reads, and
Undo/Redo after temporary writing is cleared. They use synthetic data and mocked
storage/platform callbacks.
Guided-support lifecycle regressions additionally cover expired/redacted dialogs,
covered routes, recovery admission, inactive startup, explicit preference recall,
late clipboard/deletion results and fresh confirmation after revocation.
Timer-control tests use an injected synthetic monotonic clock to verify exact
remaining time across pauses, repeated pauses and wall-clock changes, cancellation
of paused sessions, stale Start/Resume/suggestion callbacks, and large-text access
to controls. Routine reminders retain their existing start/stop and quiet-hours
behavior; pause/resume applies only to the five-minute small-step timer.

These tests do not establish clinical benefit, real-world crisis availability,
screen-reader usability or physical-device acceptance. Clinical and lived-
experience review, accessible usability testing and a measured benefit evaluation
remain needed before presenting this feature as clinically validated support.
