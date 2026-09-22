//! `neura_swarm` -- the Rust half of Neura's chat swarm: a small,
//! concurrent critic + memory-extractor pipeline that runs alongside the
//! existing Dart-side persona responder (`NeuraAiService.streamReply`,
//! unchanged). The local understanding, persona, and deterministic safety
//! foundation is exported but not yet wired into the existing WebSocket turn
//! handler. Its built-in model transport remains loopback-only. See `api.rs`
//! for the surface exposed to Dart via `flutter_rust_bridge`.

pub mod agents;
pub mod anthropic_client;
pub mod api;
pub mod brain;
mod frb_generated;
pub mod interpret;
pub mod orchestrator;
pub mod persona;
#[cfg(feature = "reqwest-transport")]
pub mod reqwest_transport;
pub mod respond;
pub mod room;
pub mod safety;

pub use brain::{BrainError, ChatMsg, CompletionOpts, LlmBrain, Role, Transport};
pub use interpret::{
    build_interpreter_messages, interpret, parse_interpretation, EmotionalRead,
    QueryInterpretation, Route, CLARIFY_THRESHOLD, INTERPRETER_SYSTEM,
};
pub use persona::{compose_system_prompt, Persona, NEURA_CHARTER};
#[cfg(feature = "reqwest-transport")]
pub use reqwest_transport::ReqwestTransport;
pub use respond::{respond, Reply};
pub use room::{NeuraTone, RoomId, RoomProfile, RoomState};
pub use safety::{
    build_safety_response, crisis_scan, GenericResources, Resource, ResourceProvider,
    SafetyResponse, StaticResources, SAFETY_MESSAGE,
};
