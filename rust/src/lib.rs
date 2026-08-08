//! `neura_swarm` -- the Rust half of Neura's chat swarm: a small,
//! concurrent critic + memory-extractor pipeline that runs alongside the
//! existing Dart-side persona responder (`NeuraAiService.streamReply`,
//! unchanged). See `api.rs` for the surface exposed to Dart via
//! `flutter_rust_bridge`.

pub mod agents;
pub mod anthropic_client;
pub mod api;
pub mod orchestrator;

// `flutter_rust_bridge_codegen generate` adds a `mod frb_generated;` line
// here (and the corresponding generated file) -- not present yet because
// codegen hasn't been run against this crate in this environment. Run
// `flutter_rust_bridge_codegen generate` from the repo root before building
// the Flutter app; `cargo build`/`cargo test` work on this crate as-is
// without it.
