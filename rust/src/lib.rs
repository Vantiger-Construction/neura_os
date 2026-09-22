//! `neura_swarm` -- the Rust half of Neura's chat swarm: a small,
//! concurrent critic + memory-extractor pipeline that runs alongside the
//! existing Dart-side persona responder (`NeuraAiService.streamReply`,
//! unchanged). The new local understanding foundation lives in `brain`,
//! `room`, and `interpret`; its built-in transport is loopback-only. See
//! `api.rs` for the surface exposed to Dart via `flutter_rust_bridge`.

pub mod agents;
pub mod anthropic_client;
pub mod api;
pub mod brain;
mod frb_generated;
pub mod interpret;
pub mod orchestrator;
#[cfg(feature = "reqwest-transport")]
pub mod reqwest_transport;
pub mod room;

pub use brain::{BrainError, ChatMsg, CompletionOpts, LlmBrain, Role, Transport};
pub use interpret::{
    build_interpreter_messages, interpret, parse_interpretation, EmotionalRead,
    QueryInterpretation, Route, CLARIFY_THRESHOLD, INTERPRETER_SYSTEM,
};
#[cfg(feature = "reqwest-transport")]
pub use reqwest_transport::ReqwestTransport;
pub use room::{NeuraTone, RoomId, RoomProfile, RoomState};
