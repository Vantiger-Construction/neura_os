# Neura chat voice commands

Open **Talk to Neura**, tap the microphone, and say a complete phrase beginning
with **Neura** or **Hey Neura**. Find the list under **Chat options → Voice
commands**. Each recognized command ends the current listening session; tap the
mic again to continue. Commands use the existing chat speech recognizer, currently
the native Windows speech bridge. Other platforms must provide that speech
channel before these microphone controls are available.

| Say | Result |
| --- | --- |
| Neura, voice help | Show the command list. |
| Neura, stop listening | End this chat's listening session and interrupt its reply. |
| Neura, stop speaking | Interrupt the current reply and stop chat listening. |
| Neura, mute replies | Mute automatic replies for this chat. |
| Neura, unmute replies | Unmute this chat if reply speech is enabled in Voice settings. |
| Neura, quiet mode | Use brief replies. |
| Neura, balanced mode | Use the default conversational style. |
| Neura, companion mode | Use the warmer companion style. |
| Neura, coach mode | Use the practical next-step style. |
| Neura, open journal | Open the existing local journal-prompt screen. |
| Neura, open mood check-in | Open the local mood form; the user still presses Save. |
| Neura, open settings | Open Settings. |
| Neura, open voice settings | Open voice and reply-speech settings. |
| Neura, where am I | Show the current Neura room. |
| Neura, open penthouse | Move to the Penthouse. “Go home” also works. |
| Neura, open reflection bay | Move to Reflection Bay. |
| Neura, open joy lounge | Move to the Joy Lounge. |
| Neura, open mood den | Move to the Mood Den. |
| Neura, open dream atrium | Move to the Dream Atrium. |
| Neura, open legacy vault | Move to the Legacy Vault. |

Controls match complete phrases from final recognition results. Partial speech,
quoted mentions, and longer compound requests do not trigger a local command.
Unrecognized speech continues through the normal chat path and its existing
cloud preview and approval rules.

Recognized commands are consumed before the chat send path. Their transcripts
are not added to chat history, model context, memory, or diagnostics. Opening a
screen grants no permission to save, share, or upload its contents. Commands
cannot approve cloud requests, change Safe Mode, enable persistent memory, or
enable background listening. Room commands only change the current local room
and its saved room selection; they do not read or write room content. Unmute
does not override the saved Off setting.

Safe Mode, ending the session, and app backgrounding invalidate pending voice
callbacks. Navigation stops capture first. Returning from a command-opened
screen or resuming the app does not restart the chat microphone automatically.

## Focused device checks

1. On Windows, tap the chat mic and try each command. Confirm the visible
   result and that the microphone stops after recognition.
2. Try a partial phrase, an ordinary chat message, and a compound request.
   Confirm controls fire only for a supported completed command, and any cloud
   chat still requires its own visible approval.
3. Start recognition, then end the conversation or enable Safe Mode while
   native stop is pending. Confirm late speech neither changes a setting nor
   opens a screen or sends a message.
4. Background the app while listening, then return. Confirm the mic stays off.
5. Open mood check-in and return without saving. Confirm no entry was created
   and listening did not restart.
6. Set reply speech to Off, then say “Neura, unmute replies.” Confirm Off remains
   selected and the app directs the user to Voice settings.
7. Open each room by voice and ask “Neura, where am I.” Confirm the room changes,
   the spoken command never enters chat history, and listening stays stopped.

The automated widget tests exercise native speech callbacks with a mocked
platform channel. A physical microphone, Windows permission prompts, and spoken
recognition accuracy still need device testing.
