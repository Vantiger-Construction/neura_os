# Neura chat voice commands

Open **Talk to Neura**, tap the microphone, and say a complete phrase beginning
with **Neura** or **Hey Neura**. Find all **39 commands**, grouped by purpose and
with short descriptions, under **Chat options → Voice commands**. Each
recognized command ends the current listening session; tap the
mic again to continue. Commands use the existing chat speech recognizer, currently
the native Windows speech bridge. Other platforms must provide that speech
channel before these microphone controls are available.

## Chat controls

| Say | Result |
| --- | --- |
| Neura, voice help | Show the command list. |
| Neura, stop listening | End this chat's listening session and interrupt its reply. |
| Neura, stop speaking | Interrupt the current reply and stop chat listening. |
| Neura, mute replies | Mute automatic replies for this chat. |
| Neura, unmute replies | Unmute this chat if reply speech is enabled in Voice settings. |
| Neura, choose companion | Open the companion picker; tap a choice to change it. |
| Neura, scroll up | Scroll up roughly one page in the current chat. |
| Neura, scroll down | Scroll down roughly one page in the current chat. |
| Neura, scroll to top | Show the first messages in the current chat. |
| Neura, scroll to bottom | Show the latest messages in the current chat. |

## Conversation style

| Say | Result |
| --- | --- |
| Neura, quiet mode | Use brief replies. |
| Neura, balanced mode | Use the default conversational style. |
| Neura, companion mode | Use the warmer companion style. |
| Neura, coach mode | Use the practical next-step style. |

## Neura rooms

| Say | Result |
| --- | --- |
| Neura, where am I | Show the current Neura room. |
| Neura, open penthouse | Move to the Penthouse. “Go home” also works. |
| Neura, open reflection bay | Move to Reflection Bay. |
| Neura, open joy lounge | Move to the Joy Lounge. |
| Neura, open mood den | Move to the Mood Den. |
| Neura, open dream atrium | Move to the Dream Atrium. |
| Neura, open legacy vault | Move to the Legacy Vault. |

## Open a screen

| Say | Result |
| --- | --- |
| Neura, open journal | Open the existing local journal-prompt screen. |
| Neura, open mood check-in | Open the local mood form; the user still presses Save. |
| Neura, open mood history | View saved mood check-ins. |
| Neura, open weekly review | View local review history; Generate remains a separate action. |
| Neura, open dream journal | View the dream journal calendar. |
| Neura, open focus | Open Focus Office without changing the selected mode. |
| Neura, open quests | View quests without marking any complete. |
| Neura, open timeline | View the local life timeline without exporting it. |
| Neura, open settings | Open Settings. |
| Neura, open voice settings | Open voice and reply-speech settings. |
| Neura, open accessibility | Open comfort and readability settings. |
| Neura, open themes | Open appearance settings. |
| Neura, open privacy | Open Privacy & Safety settings without changing consent. |
| Neura, open notifications | Open notification settings without enabling notifications. |
| Neura, open help | Open the Getting Started guide. |
| Neura, help me through this | Open guided support; choose an activity and optionally check in. |

## Next reply context

| Say | Result |
| --- | --- |
| Neura, remove selected context | Detach the selected text file from the next reply; leave the file unchanged. |
| Neura, exclude memories | Uncheck permitted memories for the next reply; retain saved memories and existing chat messages. |

Natural alternatives include **page up**, **page down**, **go to first message**,
**show latest message**, **open focus office**, **open dream calendar**,
**open appearance**, **remove selected file**, and **don't use memories**.
Guided support also accepts **open guided support** and **I need a moment**.
These still need the Neura prefix. Adding “please” at the start or end works.

## Recognition and privacy

Controls match complete phrases from final recognition results. Partial speech,
quoted mentions, and longer compound requests do not trigger a local command.
Unrecognized speech continues through the normal chat path and its existing
cloud preview and approval rules.

Recognized commands are consumed before the chat send path. Their transcripts
are not added to chat history, model context, memory, or diagnostics. Opening a
screen grants no permission to save, share, or upload its contents. Commands
cannot approve cloud requests, change Safe Mode, enable persistent memory, or
enable background listening. Room commands change the current local room and
its saved room selection without reading or writing room content. Unmute does
not override the saved Off setting.
Detaching a file or excluding memories affects only the pending next-reply
selection: it does not erase earlier chat messages or reverse an earlier share.
Existing restrictions on history derived from private context remain in force.

Safe Mode, ending the session, and app backgrounding invalidate pending voice
callbacks. Navigation stops capture first. Returning from a command-opened
screen or resuming the app does not restart the chat microphone automatically.
Commands are available in the chat screen; use the destination's Back control
to return to chat before issuing another command.

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
7. Try scrolling up, down, to the top, and to the bottom of a long conversation.
   Confirm each command stops capture and stays within the chat's bounds.
8. Select a text file and enable memories for the next reply. Remove the selected
   context, then exclude memories. Confirm the file and saved data remain intact.
9. Open Focus Office, weekly review, notifications, and the companion picker.
   Confirm opening does not change a mode, generate a review, enable notifications,
   or select a different companion. Check the remaining screen shortcuts too.
10. Open every room by voice and ask “Neura, where am I.” Confirm the room and
    displayed location agree, the command never enters chat history, and the
    microphone stays off. “Open dream room” changes rooms; “open dream calendar”
    opens the separate journal screen.

The automated widget tests exercise native speech callbacks with a mocked
platform channel. A physical microphone, Windows permission prompts, and spoken
recognition accuracy still need device testing.
