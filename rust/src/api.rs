//! The `flutter_rust_bridge` surface exposed to Dart. Kept deliberately
//! small: one `init` call (mirrors the `_safe(fn, name)`-gated service
//! init pattern already used by every other service in
//! `NeuraStartupCoordinator.boot()`) and one `review_and_extract` call per
//! chat turn.

use std::sync::atomic::{compiler_fence, Ordering};
use std::sync::Mutex;

use crate::agents::critic::CriticVerdict;
use crate::agents::memory::MemoryFact;
use crate::{anthropic_client, orchestrator};

/// Heap-backed secret bytes that are overwritten before their allocation is
/// released. The volatile writes and compiler fence keep the wipe from being
/// optimized away as a dead store.
struct SecretBytes(Vec<u8>);

impl SecretBytes {
    fn from_string(value: String) -> Option<Self> {
        let mut bytes = value.into_bytes();
        if bytes.iter().all(u8::is_ascii_whitespace) {
            wipe_bytes(&mut bytes);
            None
        } else {
            Some(Self(bytes))
        }
    }

    fn expose(&self) -> &str {
        // Constructed only from a Rust String, so this cannot be invalid UTF-8.
        std::str::from_utf8(&self.0).expect("secret originated from UTF-8 String")
    }
}

impl Clone for SecretBytes {
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl Drop for SecretBytes {
    fn drop(&mut self) {
        wipe_bytes(&mut self.0);
    }
}

fn wipe_bytes(bytes: &mut [u8]) {
    for byte in bytes {
        // SAFETY: `byte` is a valid, uniquely borrowed byte in this slice.
        unsafe { std::ptr::write_volatile(byte, 0) };
    }
    compiler_fence(Ordering::SeqCst);
}

static API_KEY: Mutex<Option<SecretBytes>> = Mutex::new(None);

/// Stores the Anthropic API key in memory only (never written to disk by
/// Rust). Dart owns OS-backed secure persistence and forwards the current
/// value at startup or after settings change. An empty value clears it.
pub fn init(api_key: String) {
    let replacement = SecretBytes::from_string(api_key);
    // Replacing the Option drops (and therefore overwrites) the old secret
    // while the mutex is held. Passing an empty value performs the same wipe.
    *API_KEY.lock().unwrap() = replacement;
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
        api_key.expose(),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_init_clears_the_process_credential() {
        init("sk-ant-test-process-secret".to_owned());
        assert!(API_KEY.lock().unwrap().is_some());

        init("   ".to_owned());
        assert!(API_KEY.lock().unwrap().is_none());
    }
}

