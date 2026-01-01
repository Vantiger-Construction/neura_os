# Legacy Module — “The Vault”

The Legacy module is Neura OS’s **private, offline-first memory vault**.
It’s meant for letters, wisdom, instructions, and “if something happens to me” capsules — **stored locally** and exportable as shareable packets.

## What’s included

### Capsules
- Create capsules with: title, message, recipients, tags
- Optional **time-lock** (unlock date)
- Optional **seal** (read-only)
- Optional **encryption** (AES‑GCM via `cryptography`)
- Attach files (stored locally)

### Trusted Contacts
A reusable list of people or destinations for delivery (email, handle, etc.).

### Delivery mode
Each capsule can be marked **Delivery enabled** with:
- Trigger: `manual`, `unlock`, or `deadman` (Legacy Guard)
- Preferred format: `zip`, `pdf`, or `json`

### Legacy Guard (dead-man switch style)
- User sets a check-in interval + grace period
- If overdue, Neura prompts the user to check in or prepare delivery packets
- Packets are shared using the OS share sheet (email/text/file drop)

## Files
- Vault root: app documents directory
- Capsule JSON: `capsule_<id>.json`
- Attachments: `capsule_<id>/attachments/*`
- Exports: temporary directory (`/tmp`-equivalent)

## Privacy + safety notes
- The vault is local-only by default.
- Encryption protects message text; attachments are stored locally and can be included in packets.
- For true “auto send”, you’ll need a backend (email/SMS service). This build intentionally stays offline-first.
