# Neura local brain (`neura_api`)

A same-device WebSocket service the app's Neura Link console connects to
(`ws://127.0.0.1:8787`). Build and run with `tools/Build-Neura-LocalBrain.ps1 -Run`.
It is separate from the opt-in *Local app API* (`docs/NEURA_API_SYSTEM_UPGRADES.md`).

## Behavior

- Envelope: `{"v":1,"kind":"...","id":"...","data":{...}}`.
- Inbound kinds: `hello`, `room_entered`, `diagnostics_request`, `user_text`, `interrupt`.
- Outbound kinds: `hello`, `set_tone`, `diagnostics`, `speak_delta`, `speak`,
  `speak_interrupted`, `error` (`data.code` + `data.message`).
- `hello` replies with `capabilities` and `limits` (`max_text_chars`, `max_frame_bytes`).
- `room_entered` maps the app's current room ids to a tone (`penthouse` → focused,
  `reflection_bay`/`dream_atrium` → calm, `joy_lounge` → hopeful, others → warm).
- A new `user_text`, or an explicit `interrupt`, cancels the streaming reply and emits
  `speak_interrupted` for it.
- `diagnostics.generated_at` is RFC 3339 UTC so the app can parse it.
- `GET /health` returns content-free readiness JSON.

## Boundaries

- Loopback only. A non-loopback `NEURA_API_ADDR` is refused unless
  `NEURA_API_ALLOW_NONLOOPBACK=1`.
- Handshakes carrying an `Origin` header (browsers) get 403.
- Messages over 64 KiB are dropped by the socket layer; `text` over 8,000 characters
  returns an `error` frame with `text_too_long` and does not interrupt the current reply.
- Outbound queue is bounded (256 frames) so a stalled client cannot grow memory.
- The model adapter is still a local echo provider (reported as `degraded` in
  diagnostics). No cloud calls are made from this service.
