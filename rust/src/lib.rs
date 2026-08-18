//! `neura_swarm` -- the Rust half of Neura's chat swarm: a small,
//! concurrent critic + memory-extractor pipeline that runs alongside the
//! existing Dart-side persona responder (`NeuraAiService.streamReply`,
//! unchanged). See `api.rs` for the surface exposed to Dart via
//! `flutter_rust_bridge`.

pub mod agents;
pub mod anthropic_client;
pub mod api;
mod frb_generated;
pub mod orchestrator;
