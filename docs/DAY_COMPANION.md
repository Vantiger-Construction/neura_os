# Day Companion

Open **Day Companion** from the main menu’s command search or **Chat options**. Tap **Start listening locally** while the app is in the foreground. Use a space where everyone agrees to be heard. The recognizer hears nearby speech and cannot identify the speaker. Windows needs an installed SAPI recognizer. Android needs an available on-device recognizer. An ordinary Android silence timeout starts another listening window after a short pause. A microphone or recognizer failure ends the session. Tap Start again to resume.

## Penthouse and notes

Try “I’m winding down”. Neura switches off the penthouse lamp and closes the curtains. “I need to focus” switches on the reading light and closes the curtains. You can also ask for the lamp or curtains individually, undo the last change, or turn off room adjustments.

Try “I promised to bring the sketchbook tomorrow” or “I prefer the window seat”. Recognized first-person commitments, plans, appointments, preferences and explicit “remember” requests can become editable drafts. Review what Neura actually heard. Tap **Save note** to keep the edited text in encrypted companion notes. Open **Chat options → Companion notes** to review, correct or forget it later. Chat has a separate control to include saved notes in a reply.

Twelve drafts fit in a session. Pause to review them. Leaving the screen, switching apps, entering Safe Mode or restarting clears unsaved drafts and device links. This session sends no audio or transcripts to the hub. Ambient audio clips and the Hey Neura feature have their own controls in Privacy.

## Connecting real devices

Neura can call named Home Assistant automations. Home Assistant must already have access to the device. Each link is a secret for a single configured automation. You can make one from the automation editor or use the included blueprint.

1. Copy `integrations/home_assistant/day_companion.yaml` to `config/blueprints/automation/neura/day_companion.yaml` on your Home Assistant system. Reload automations. Under **Settings → Automations & scenes → Blueprints**, create an automation from **Neura Day Companion home action**.
2. Generate a different random secret for each action. Select the device and the exact action in the Home Assistant editor. The blueprint accepts local PUT requests. In the manual editor, choose a webhook trigger, enable PUT and keep local-only enabled.
3. In **Day Companion → Real devices**, enter a short name identifying the device and the change. Enter the local webhook URL ending in `/api/webhook/<secret>`. Use the hub’s private IP or a `.local` hostname. HTTPS verifies the hub certificate. On a trusted LAN, HTTP sends the secret in cleartext.
4. Optionally link one action to focusing or winding down. Neura can then offer that action when she hears the cue. Say “Neura, turn on the desk light” for an action named **Turn on the desk light**, or tap its name. Review the name and hub, then tap **Run once** within one minute. The request has an empty body. A receipt only confirms the HTTP response. Use Home Assistant’s automation trace and the actual device to check execution.

| Example name in Neura | Fixed action configured in Home Assistant |
| --- | --- |
| Turn on the desk light | Use `light.turn_on` for one Philips Hue light. Add a separate off action if wanted. |
| Use the hallway thermostat eco preset | Use `climate.set_preset_mode` for that thermostat and select a supported preset. For a fixed temperature use `climate.set_temperature`, check the unit in Home Assistant, and include the number and unit in the Neura name. |
| Play a chime on the kitchen Echo | Use `alexa_devices.send_sound` for that Echo and choose the chime. Alexa Devices uses Amazon’s cloud. |
| Turn on the reading fan | Use the fan action for the specific fan entity that Home Assistant exposes. |

The hub controls what each link does. Update the name if you change the automation. Remove or disable that automation in Home Assistant to revoke its secret. Keep actual URLs out of screenshots, logs and bug reports.

[Home Assistant webhook trigger](https://www.home-assistant.io/triggers/webhook/) · [Philips Hue](https://www.home-assistant.io/integrations/hue/) · [Climate](https://www.home-assistant.io/integrations/climate/) · [Alexa Devices](https://www.home-assistant.io/integrations/alexa_devices/)
