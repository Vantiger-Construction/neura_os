# Neura API understanding foundation

This integration adds the supplied pre-generation understanding stage to the
existing Rust sidecar crate under `rust/`. It does not create a duplicate
runtime or replace the Flutter secure model router.

## Source layout

- `rust/src/brain.rs`: transport-abstracted, OpenAI-compatible local brain.
- `rust/src/reqwest_transport.rs`: built-in HTTP transport, restricted to
  loopback endpoints. Cloud requests must continue through Neura's visible
  fresh-approval router.
- `rust/src/room.rs`: room behavior, tool allow-lists, privacy persistence,
  and request/confirmation movement state.
- `rust/src/interpret/`: interpreter prompt, structured
  `QueryInterpretation`, deterministic crisis-language redundancy, parsing,
  fallback, and safety-route precedence.

## Validation

Run from the repository root:

```bash
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo test --manifest-path rust/Cargo.toml
cargo build --manifest-path rust/Cargo.toml --bin neura_api
```

The source includes offline unit coverage for request/response contracts,
interpretation parsing and fallback, model-plus-deterministic safety precedence,
room privacy and tool boundaries, movement confirmation, and loopback-only
transport enforcement.

## Runtime wiring boundary

The foundation is compiled into the existing Rust library but is not invoked by
the current `user_text` WebSocket handler. Activating it later must preserve:

1. Safe Mode cancellation and microphone shutdown.
2. Fresh visible approval for every cloud request and fallback.
3. Room-scoped tool allow-lists and Action Loom authority.
4. The no-background-cloud boundary.
5. Current, region-appropriate safety resources rather than hardcoded numbers.
