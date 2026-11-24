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

# Second set: style, weather, morning notes, honest facts

## Learns your style

Each finished reply has a thumbs up and down. `NeuraStyleMemory` keeps up
to 10 liked exchanges and the word counts of the last 40 ratings, encrypted
with the device memory key. For the on-device model only, the system prompt
gains up to two liked exchanges closest to the new message ("match their
tone and length, not their content") and a length hint learned from ratings
("They prefer short replies."), within 900 bytes. Nothing is retrained and
nothing reaches a cloud prompt; profile sessions and reference answers never
use it. Chat menu → **Forget what I've learned from ratings** clears it.

## Mood weather room

`NeuraMoodWeather` reads the last 7 days of mood check-ins: an average of 7+
is a warm clear glow, under 5 a soft haze, under 3.5 light rain on the
glass; fewer than 3 check-ins leaves the room as it is. The layer is static
(no animation) and subtle. It refreshes on launch and after each check-in,
resets on a data wipe, and profile sessions never read mood history.

## Morning notes

Off until the user turns on chat menu → **Morning notes**. On the first open
of a new day (after 4 a.m.), the on-device model writes two or three gentle
sentences about yesterday from the user's own mood check-ins and journal
entries (chat conversations are not stored, so they are not used). It shows
as a dismissible banner in chat.

- Offline only (`NeuraAiService.offlineNote`), with guardrails on the prompt
  and the reply; any crisis language in yesterday's notes means no note.
- One attempt per day, even if the model fails. Only today's note is kept,
  encrypted; turning the feature off deletes it.

## Honest offline facts

After a screened offline answer, `NeuraFactCheck` adds one line when a
factual question ("when", "how many", "what is", prices, doses...) got an
answer with specifics (numbers, years, months, amounts): Neura says she is
answering from memory and points to the offline reference shelf for a
source-checked answer. Any dose or medicine amount gets "check with a
pharmacist or doctor" instead. The reference shelf itself is not searched
automatically: its passages reach the model only through a grant the user
gives with a direct tap. The offline instructions are unchanged: they were
tuned against the real model and sit at their 6500-byte budget, so the
caveat is added in code instead of asking the model.

# Third set: everyday help and gentle creativity

The chat menu's **Companion tools…** sheet gathers the screens below (and
Rehearse a hard talk), plus the On this day switch.

## Worry parking and worry time

"Park it: ..." (or "park this worry: ...") sets a worry aside instead of
sending it: `NeuraWorryParking` encrypts it with the device memory key, keeps
up to 30, and never puts them in a model prompt. At the worry time the user
picks (6 p.m. by default), chat offers once a day to look at the worries
parked before it. **Worry time** sorts each one: a small step, let it go
(deleted), or keep for later (back at the next worry time).

Crisis language is never parked or filed as a note to future you: it goes
through the normal reply and its guardrails instead.

## Before you send

Paste a message before sending it. `NeuraToneCheck` notes, on this device,
how it might land (a hard feeling, blame like "you never", insults, sarcasm,
capitals, exclamation marks). **Suggest a calmer version** asks the model to
keep the meaning and voice without blame or invented apologies (offline, or
cloud with approval; guardrails on both sides; a guardrail answer is never
shown as a rewrite). The user copies whichever version they choose. Nothing
is saved.

## Gratitude moments (bright spots)

When a message reads clearly happy (joy at 0.6+ intensity and no harder
second feeling), chat offers once a day: "That sounds like a bright spot.
Keep it for a harder day?" Bright spots are stored with the notes to future
you (a `brightSpot` kind), come back on hard days after any written notes,
and appear in the next morning's note.

## On this day

Off until switched on in Companion tools. Once a day at most, a memory from
a year ago today (or a month ago): a journal line, a check-in note or the
day's best check-in. A day with any check-in under 5/10, a hard feeling in
its notes, an "I'm fine" that reads otherwise or crisis language never comes
back uninvited.

## Weather-matched sound

The bundled ambient sounds were text placeholders, so the Ambient sound
switch played nothing. `tools/generate_ambient_sounds.py` now builds real,
seamless 30-second loops from shaped noise (room tone, ocean, wind, slow
breathing, and new rain); no recordings or third-party audio. When the mood
weather is rain, the room's ambient loop becomes soft rain.

## Focus together (body doubling)

Pick a task and 15 to 60 minutes. Neura's room stays behind a calm timer,
she says one line at the start, checks in at halfway, and celebrates the
finish (her avatar hops). Only a count of finished sessions is kept, never
the task.

## Mood gallery

Each week of check-ins becomes a small abstract painting
(`NeuraMoodPainting`): the background from the week's average mood, one
brushstroke per check-in placed by day and mood, as thick as that day's
energy and as long as the sleep. Deterministic for each week. The gallery
shows up to 26 weeks; **Save image** exports a PNG only when asked.

## Bedtime stories

Pick a setting (forest, sea, stars, cabin, garden) and optionally something
to include. The model writes a calm 250-word story with nothing frightening
or exciting; Neura reads it paragraph by paragraph in a slow, soft bedtime
tone (each chunk stays well under the speech timeout), with a sleep timer of
10, 20 or 30 minutes. Nothing is saved.
