# Help me through this

Open the button in Talk to Neura, Care Loop, or Support Center. In chat, with
the microphone explicitly started, say **Neura, help me through this**. The
aliases **Neura, open guided support** and **Neura, I need a moment** work too.
Native capture stops before navigation and stays off when returning to chat.
This uses the existing native Windows speech bridge; it does not add an offline
ASR engine or Android voice support. The button and activities work without ASR.

## Experience

- **Quiet writing:** optional temporary writing followed by a gentle reflection.
- **Grounding pause:** three short prompts to notice comfortable details nearby.
- **One small plan:** choose one concern, one manageable action, and when to try it.

Users advance at their own pace, go back, switch activities, or leave at any
point. No timer, streak, reward, or automatic microphone competes for attention.
The optional final check-in offers helped, about the same, worse, or unsure.
Worse leads to stopping and offering other support, not a success message.
Reach a person is available throughout, with the existing locale-specific
support wording and access to trusted contacts. It never sends a message or
makes a call for the user.

## Permission and storage

The fixed activities run locally without model calls. Temporary writing is
held only in text controllers, never analyzed, logged, copied, or saved by the
feature. It clears on finishing, switching activities, opening human support,
leaving the screen, backgrounding, or entering Safe Mode. Keyboard services are
controlled by the device; this flow disables suggestions and autocorrection.

A helpful check-in does not grant permission to remember. A separate confirmation
names the exact activity, explains its future use, and states that it replaces
the previous preference. Only an activity identifier, confirmation time, schema
version, and `suggest_in_guided_support` scope are persisted. The record implies
that the user marked this activity helpful; it contains no writing or check-in
history. It uses the existing MemoryCrypto AES-GCM device key and an encrypted
SharedPreferences value, with no plaintext fallback. No new key store is added.

Recall is limited to this screen and explains “You asked Neura to remember…”.
It never changes the selected activity automatically or enters AI memory/context.
The bookmark button shows the record, explicitly copies its full JSON to the
clipboard on request, or forgets it. To change the preference, try another activity
and confirm remembering it. Reading errors remain visible, and forgetting works
even when the record cannot be opened. Full local data wipe drains this writer,
deletes the preference, and revokes queued writes. Safe Mode permits manual fixed
activities and deletion but blocks preference reading and saving. Backgrounding,
leaving, and Safe Mode invalidate pending confirmation.

No cloud approval, journaling, sync, reminders, or background learning is enabled
by opening or completing this flow. Existing cloud approvals remain unchanged.
The new preference is separate from the pending encrypted-memory foundation PR.

## Content basis and release checks

The prompts are original, brief wellness content informed by
[Oxford Health's grounding guidance](https://oxfordhealth.nhs.uk/camhs/self-care/sleep/relaxation/ground-yourself/)
and [NHS Every Mind Matters problem solving](https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/self-help-cbt-techniques/problem-solving/),
checked September 26, 2026. These references do not establish effectiveness of
Neura's implementation. No clinician review or comparative study has been
performed. Do not market this as treatment or as superior to other wellness apps.

Automated coverage includes all three entry points, all three activity paths,
exact voice-command and alias boundaries, native-stop ordering, encrypted scoped
persistence, restart/replace/inspect/copy/forget behavior, unavailable credentials,
data wipe, backgrounding, Safe Mode during a pending save, temporary text clearing,
negative feedback, dark mode, 200% text and a narrow screen. The repository's full
Flutter validation discovers these tests automatically.

The reproducible mapping and the manual result form are in
[NEURA_GUIDED_SUPPORT_RELEASE_EVIDENCE.md](release-evidence/NEURA_GUIDED_SUPPORT_RELEASE_EVIDENCE.md).
That record intentionally leaves physical Windows and Android evidence marked
**NOT COLLECTED**. A mock platform channel, widget test or successful package build
must not be recorded as physical-device evidence.

Before general release, perform these device checks on Windows and Android:

1. Open all three entry points and complete or exit every activity offline.
2. On Windows, try the addressed voice command and aliases with a real microphone.
   Confirm partial, quoted and compound speech does not navigate; returning leaves
   the mic off. Android should offer the button without requiring the speech bridge.
3. Remember one activity, close and restart the app, inspect its explanation,
   copy the preference, replace it, and forget it. Test unavailable OS credentials.
4. Background while writing or confirming, enter Safe Mode during a save, and
   wipe local data. Confirm no writing returns and no preference is recreated.
5. Check keyboard navigation, a screen reader, 200% text, dark mode and narrow
   windows. Each prompt must remain skippable and human support easy to reach.

## Small pilot proposal

After content review and device checks, invite consenting adult testers to a
short usability pilot. Keep feedback separate from app memories. Ask whether
they could find support, whether the selected activity helped, felt neutral or
felt worse, whether they understood exactly what was remembered, and whether
they could remove it. Record navigation or permission failures without private
writing or speech. Participation and each response should be optional.

Review unwanted effects and confusing consent first, then revise the content
and navigation. This pilot is proposed, not conducted, and cannot demonstrate
clinical benefit or superiority. Longer-term evaluation needs its own protocol.
