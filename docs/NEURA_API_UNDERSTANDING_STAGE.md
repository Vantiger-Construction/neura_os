# Neura API understanding, character, and safety foundation

This integration adds the supplied pre-generation understanding, persona, and
deterministic safety layers to the existing Rust sidecar crate under `rust/`.
It does not create a duplicate runtime, replace the Flutter secure model
router, or change the current chat and speech paths.

## Source layout

- `rust/src/brain.rs`: transport-abstracted, OpenAI-compatible local brain.
- `rust/src/reqwest_transport.rs`: built-in HTTP transport restricted to
  loopback endpoints. Cloud requests must continue through Neura's visible
  fresh-approval router.
- `rust/src/room.rs`: room behavior, tool allow-lists, privacy persistence,
  and request/confirmation movement state.
- `rust/src/interpret/`: structured interpretation, parsing, fallback, and
  redundant safety-route precedence.
- `rust/src/persona.rs`: Neura's stable, warm, honest companion charter,
  composed ahead of room-specific behavior.
- `rust/src/safety.rs`: deterministic crisis-language scan, reviewed response,
  and injectable region-aware human-support resources.
- `rust/src/respond.rs`: per-turn orchestration. Deterministic safety runs
  before any model call; the model safety route is a second independent net.

## Validation

Run from the repository root:

```bash
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo test --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml --features reqwest-transport
cargo build --manifest-path rust/Cargo.toml --bin neura_api
```

The source includes offline unit coverage for request/response contracts,
interpretation parsing and fallback, deterministic and model-assisted safety
precedence, reviewed-resource fallbacks, persona limits, room privacy and tool
boundaries, movement confirmation, and loopback-only transport enforcement.

## Runtime wiring boundary

These modules are compiled into the existing Rust library but are not invoked
by the current `user_text` WebSocket handler. Memory, knowledge, and tool routes
remain non-executing integration seams. Activating them later must preserve:

1. Safe Mode cancellation and microphone shutdown.
2. Fresh visible approval for every cloud request and fallback.
3. `off`, `afterComplete`, and `streamed` reply-speech behavior.
4. Room-scoped tool allow-lists and Action Loom authority.
5. The no-background-cloud boundary.
6. Local journaling as authoritative unless the user explicitly enables sync.
7. Current, region-appropriate safety resources rather than hardcoded numbers.

The supplied standalone manifest was not copied over the existing
`rust/Cargo.toml`: the repository manifest already contains the full sidecar
dependency set and the optional `reqwest-transport` feature. No dependency or
workflow change is required for this layer.
