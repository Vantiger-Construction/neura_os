//! Per-turn response orchestration: local safety check, interpretation, route,
//! and reply generation with Neura's persona composed into the room prompt.

use crate::brain::{ChatMsg, CompletionOpts, LlmBrain, Transport};
use crate::interpret::{interpret, Route};
use crate::persona::{compose_system_prompt, Persona};
use crate::room::RoomProfile;
use crate::safety::{build_safety_response, crisis_scan, ResourceProvider, SafetyResponse};

/// What Neura decides to say for a turn.
#[derive(Debug, Clone)]
pub enum Reply {
    /// A generated conversational reply.
    Text(String),
    /// A short clarifying question, asked instead of guessing.
    Clarify(String),
    /// A reviewed crisis response plus human-support resources.
    Safety(SafetyResponse),
}

const CLARIFIER: &str =
    "I want to make sure I really understand before I answer — can you tell me a little more \
about what you mean?";

const GENTLE_FALLBACK: &str =
    "I'm here with you — I had a hiccup just then. Could you say that again for me?";

/// Handle one turn end to end.
///
/// Precedence is deliberate:
/// 1. Deterministic safety scan before any model or transport call.
/// 2. Model-assisted interpretation, whose safety route also wins.
/// 3. Clarification rather than guessing.
/// 4. Memory, knowledge, tool, or chat routing.
///
/// Memory, knowledge, and tool retrieval remain explicit integration seams.
/// Until those subsystems are wired, they execute no action and add no context;
/// the responder generates a plain local reply from the resolved query.
pub fn respond<T, R>(
    brain: &LlmBrain<T>,
    persona: &Persona,
    room: &RoomProfile,
    resources: &R,
    history: &[ChatMsg],
    turn: &str,
    locale: Option<&str>,
) -> Reply
where
    T: Transport,
    R: ResourceProvider,
{
    // Safety is local and synchronous. A matching turn never reaches a model.
    if crisis_scan(turn) {
        return Reply::Safety(build_safety_response(resources, locale));
    }

    let interpretation = interpret(brain, turn, history);

    if interpretation.route == Route::Safety {
        return Reply::Safety(build_safety_response(resources, locale));
    }

    if interpretation.should_clarify() {
        return Reply::Clarify(CLARIFIER.to_string());
    }

    let system = compose_system_prompt(persona, room);
    let mut messages = Vec::with_capacity(history.len() + 2);
    messages.push(ChatMsg::system(system));
    messages.extend(history.iter().cloned());
    messages.push(ChatMsg::user(interpretation.resolved_query));

    match brain.complete_once(&messages, CompletionOpts::default()) {
        Ok(text) => Reply::Text(text),
        Err(_) => Reply::Text(GENTLE_FALLBACK.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::brain::{test_support::FakeTransport, BrainError};
    use crate::room::RoomId;
    use crate::safety::GenericResources;

    struct PanicTransport;

    impl Transport for PanicTransport {
        fn post_json(&self, _url: &str, _body: &str) -> Result<String, BrainError> {
            panic!("deterministic safety path must not call a model")
        }
    }

    fn brain_returning(response: &str) -> LlmBrain<FakeTransport> {
        LlmBrain::new(
            FakeTransport::new(response),
            "http://localhost:1234/v1",
            "local",
        )
    }

    #[test]
    fn deterministic_crisis_turn_never_calls_the_model() {
        let brain = LlmBrain::new(PanicTransport, "http://localhost:1234/v1", "local");
        let reply = respond(
            &brain,
            &Persona::default(),
            &RoomProfile::default_for(RoomId::Welcome),
            &GenericResources,
            &[],
            "I don't want to be alive anymore",
            Some("en-US"),
        );
        assert!(matches!(reply, Reply::Safety(_)));
    }

    #[test]
    fn model_safety_route_takes_precedence() {
        let response = r#"{"choices":[{"message":{"content":"{\"intent\":\"seeking_support\",\"resolved_query\":\"help\",\"ambiguity\":0.1,\"crisis_signal\":true,\"route\":\"chat\"}"}}]}"#;
        let reply = respond(
            &brain_returning(response),
            &Persona::default(),
            &RoomProfile::default_for(RoomId::Welcome),
            &GenericResources,
            &[],
            "nothing feels manageable",
            Some("en-US"),
        );
        assert!(matches!(reply, Reply::Safety(_)));
    }

    #[test]
    fn high_ambiguity_asks_instead_of_answering() {
        let response = r#"{"choices":[{"message":{"content":"{\"intent\":\"unknown\",\"resolved_query\":\"?\",\"ambiguity\":0.9,\"route\":\"chat\"}"}}]}"#;
        let reply = respond(
            &brain_returning(response),
            &Persona::default(),
            &RoomProfile::default_for(RoomId::Lounge),
            &GenericResources,
            &[],
            "you know?",
            None,
        );
        assert!(matches!(reply, Reply::Clarify(_)));
    }
}
