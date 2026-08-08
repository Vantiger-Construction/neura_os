//! The `flutter_rust_bridge` surface exposed to Dart. Kept deliberately
//! small: one `init` call (mirrors the `_safe(fn, name)`-gated service
//! init pattern already used by every other service in
//! `NeuraStartupCoordinator.boot()`) and one `review_and_extract` call per
//! chat turn.

use std::sync::Mutex;

use crate::agents::critic::CriticVerdict;
use crate::agents::memory::MemoryFact;
use crate::{anthropic_client, orchestrator};

static API_KEY: Mutex<Option<String>> = Mutex::new(None);

/// Stores the Anthropic API key in memory only (never written to disk by
/// Rust) -- same key already baked into the Dart build via
/// `--dart-define=ANTHROPIC_API_KEY`, just forwarded here once at startup.
/// Safe to call more than once (e.g. Flutter hot-restart during dev).
pub fn init(api_key: String) {
    *API_KEY.lock().unwrap() = Some(api_key);
}

/// Runs the critic + memory-extractor agents for one finished chat turn.
/// Returns immediately with safe defaults (pass verdict, no facts) if
/// `init` was never called -- the swarm is an enhancement, never a blocker
/// for the primary chat reply, which has already been shown by the time
/// this is invoked.
pub async fn review_and_extract(
    transcript: String,
    draft_reply: String,
    user_message: String,
) -> SwarmOutcome {
    let api_key = API_KEY.lock().unwrap().clone();
    let Some(api_key) = api_key else {
        return SwarmOutcome {
            verdict: SwarmVerdict::Pass,
            facts: Vec::new(),
        };
    };

    let outcome = orchestrator::handle_turn(
        anthropic_client::default_endpoint(),
        &api_key,
        &transcript,
        &draft_reply,
        &user_message,
    )
    .await;

    SwarmOutcome::from(outcome)
}

/// FFI-friendly mirror of [`crate::orchestrator::AgentResults`] -- kept as a
/// separate type (rather than exposing the internal one directly) so the
/// Rust-internal orchestrator/agent modules stay free to evolve without
/// touching the generated Dart API surface.
pub struct SwarmOutcome {
    pub verdict: SwarmVerdict,
    pub facts: Vec<SwarmFact>,
}

pub enum SwarmVerdict {
    Pass,
    Concern { note: String },
}

pub struct SwarmFact {
    pub summary: String,
    pub kind: String,
}

impl From<orchestrator::AgentResults> for SwarmOutcome {
    fn from(o: orchestrator::AgentResults) -> Self {
        SwarmOutcome {
            verdict: match o.verdict {
                CriticVerdict::Pass => SwarmVerdict::Pass,
                CriticVerdict::Concern { note } => SwarmVerdict::Concern { note },
            },
            facts: o
                .facts
                .into_iter()
                .map(|MemoryFact { summary, kind }| SwarmFact { summary, kind })
                .collect(),
        }
    }
}
