# Companion ideas: voice, listening, notes, rehearsal

Four features that make Neura feel more present. All run on this device
except a rehearsal the user chooses to send to the cloud, which asks first.

## Voice that matches mood

`NeuraVoiceTone` turns the on-device `EmotionRead` of the user's latest
message into small multipliers on their own speech rate and pitch:

- Hard feelings (sadness, grief, loneliness, shame, exhaustion): slower and a
  touch lower.
- Tense feelings (anxiety, overwhelm, anger): slower, an even pitch.
- Clear good news: a little brighter. Mixed "relieved but exhausted" is not.
- Crisis language: always the calm, steady tone.

The lean is at most about 12%, scaled by intensity, and applies only to the
next replies. Voice previews play the saved settings exactly. Voice settings
has a **Match my mood** switch (on by default).

## Patient listening

Hands-free voice used to reply at the first recognized pause. Now each SAPI
phrase is collected and the turn ends after `NeuraTurnPatience`:

- 0.7 s after a finished-sounding phrase.
- 1.4 s when the emotion read finds a hard feeling.
- 2.6 s when the words trail off ("and", "but", "um", a trailing comma).

More speech cancels the wait. The input shows "Take your time, I'm
listening." while it waits for the rest of a thought. Voice commands still
act at once. The whole turn, not only its last phrase, is sent.

## Notes to future you

"Note to future me: ..." (or "note for my future self") saves the note on
this device instead of sending it anywhere. `NeuraFutureNotes` encrypts the
list with the device memory key (`MemoryCrypto`), keeps at most 20 notes of
up to 600 characters, and a local data wipe erases them.

After Neura answers a hard moment (a clear hard feeling or "I'm fine" that
reads otherwise), she may offer: "You once left yourself a note for a day
like this." Rules:

- Never after crisis language, in profile sessions or in Safe Mode.
- Not within a day of writing a note, and at most one offer per 3 days.
- The least recently offered note comes back first.
- Notes never enter a model prompt; only the user reads them, and they can
  delete one from the note dialog.

## Rehearse a hard talk

Chat menu → **Rehearse a hard talk** (not in profile sessions). The user
names who the talk is with, what they want to say, and how the person might
react (open, guarded, upset). Neura plays that person in short spoken lines,
realistic but never cruel, insulting or threatening, and steps out of the role
if the user seems truly distressed. **How did I do?** gives brief coaching:
one thing that went well, one thing to try, and an opening line.

`NeuraAiService.rehearsalTurn` screens the user's line and the reply with
the chat guardrails; a block shows the safe alternative and ends the
practice. Offline it uses Ollama; with a cloud provider each request shows
the usual approval preview. Practice transcripts are bounded (3.5 KB) and
never saved.
