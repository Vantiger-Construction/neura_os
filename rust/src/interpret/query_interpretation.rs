//! Pre-generation understanding stage.
//!
//! Runs once per turn, BEFORE the brain generates a reply, turning a raw turn
//! into an inspectable `QueryInterpretation` (resolved query, intent, emotional
//! read, safety signal, route).
//!
//! Field roles:
//!   - `intent` / `entities` / `emotional_read` are DESCRIPTIVE — for logging
//!     and tone. Nothing branches on them.
//!   - `route` is the ONE field the pipeline branches on. Keep it total + small.
//!
//! Safety: `crisis_signal` is the model's opinion. For a wellness app, pair it
//! with a deterministic check and let EITHER trip `Route::Safety`. When unsure,
//! route to Safety — a false Safety is cheap, a missed one is not.

use serde::{Deserialize, Serialize};

use super::interpreter_prompt::build_interpreter_messages;
use crate::brain::{ChatMsg, CompletionOpts, LlmBrain, Transport};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryInterpretation {
    /// snake_case intent label, e.g. "seeking_support". Loggable, not branched on.
    pub intent: String,

    /// People / topics / places the turn names. Feeds memory recall.
    #[serde(default)]
    pub entities: Vec<String>,

    /// The turn rewritten to stand alone, pronouns resolved. Downstream uses this.
    pub resolved_query: String,

    /// 0.0 = clear, 1.0 = genuinely unclear. Above `CLARIFY_THRESHOLD`, ask.
    pub ambiguity: f32,

    /// Rough read of the person's state, for tone. `None` when no signal.
    #[serde(default)]
    pub emotional_read: Option<EmotionalRead>,

    /// Model's flag for possible crisis / self-harm / acute distress. Not the
    /// sole safety check — see module note.
    #[serde(default)]
    pub crisis_signal: bool,

    /// Where the pipeline sends this turn next.
    pub route: Route,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Route {
    /// Plain conversational reply. No retrieval, no tools.
    Chat,
    /// Needs episodic/semantic recall from neura-memory first.
    Memory,
    /// Needs a room-scoped tool call (RoomProfile allow-list).
    Tool,
    /// Needs grounding in the knowledge base (RAG).
    Knowledge,
    /// Distress / crisis: suppress advice mode, respond with care, surface real
    /// human resources. Highest priority — overrides all others.
    Safety,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmotionalRead {
    pub primary: String,
    pub intensity: f32,
}

/// Ambiguity at/above this should trigger a clarifying question upstream.
pub const CLARIFY_THRESHOLD: f32 = 0.6;

impl QueryInterpretation {
    /// Conservative fallback when the interpreter call fails or won't parse.
    /// Never drops the turn.
    pub fn fallback(raw_turn: &str) -> Self {
        Self {
            intent: "unknown".to_string(),
            entities: Vec::new(),
            resolved_query: raw_turn.to_string(),
            ambiguity: 1.0,
            emotional_read: None,
            crisis_signal: false,
            route: Route::Chat,
        }
    }

    /// Force safety precedence AFTER parsing: a model that flags distress but
    /// mis-routes still lands on Safety. Call before acting on `route`.
    pub fn enforce_safety(mut self) -> Self {
        if self.crisis_signal {
            self.route = Route::Safety;
        }
        self
    }

    /// Apply both the model signal and a deterministic local pass. Either one
    /// is sufficient to select the safety route.
    pub fn enforce_safety_for_turn(mut self, raw_turn: &str) -> Self {
        if self.crisis_signal || deterministic_crisis_signal(raw_turn) {
            self.crisis_signal = true;
            self.route = Route::Safety;
        }
        self
    }

    /// True when ambiguity is high enough to ask a clarifying question instead
    /// of committing to an answer.
    pub fn should_clarify(&self) -> bool {
        self.ambiguity >= CLARIFY_THRESHOLD
    }
}

/// Interpret one turn using the brain. `history` is the last few turns, for
/// coreference resolution. Never errors: on any failure, returns a safe
/// fallback so the caller always gets a route.
pub fn interpret<T: Transport>(
    brain: &LlmBrain<T>,
    raw_turn: &str,
    history: &[ChatMsg],
) -> QueryInterpretation {
    let messages = build_interpreter_messages(raw_turn, history);
    match brain.complete_once(&messages, CompletionOpts::interpreter()) {
        Ok(text) => parse_interpretation(&text, raw_turn),
        Err(_) => QueryInterpretation::fallback(raw_turn).enforce_safety_for_turn(raw_turn),
    }
}

/// Parse a model completion into an interpretation, tolerating fences/prose.
/// Falls back rather than erroring.
pub fn parse_interpretation(completion: &str, raw_turn: &str) -> QueryInterpretation {
    let cleaned = strip_json_fences(completion);
    match serde_json::from_str::<QueryInterpretation>(&cleaned) {
        Ok(interp) => interp.enforce_safety_for_turn(raw_turn),
        Err(_) => QueryInterpretation::fallback(raw_turn).enforce_safety_for_turn(raw_turn),
    }
}

/// Conservative, local redundancy for unambiguous crisis language. This is
/// deliberately small: it supplements the interpreter and does not diagnose.
fn deterministic_crisis_signal(raw_turn: &str) -> bool {
    let normalized = raw_turn
        .to_lowercase()
        .replace('’', "'")
        .replace('-', " ");
    const CRISIS_PHRASES: &[&str] = &[
        "kill myself",
        "end my life",
        "take my life",
        "hurt myself",
        "self harm",
        "want to die",
        "suicidal",
        "suicide",
        "do not want to live",
        "don't want to live",
        "no reason to live",
        "better off dead",
    ];
    CRISIS_PHRASES
        .iter()
        .any(|phrase| normalized.contains(phrase))
}

/// Slice a bare JSON object out of a completion that may be fenced or prefixed.
fn strip_json_fences(s: &str) -> String {
    let s = s.trim();
    let s = s
        .strip_prefix("```json")
        .or_else(|| s.strip_prefix("```"))
        .unwrap_or(s);
    let s = s.strip_suffix("```").unwrap_or(s).trim();
    match (s.find('{'), s.rfind('}')) {
        (Some(a), Some(b)) if b > a => s[a..=b].to_string(),
        _ => s.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fallback_is_safe_and_lossless() {
        let f = QueryInterpretation::fallback("what do I do about it");
        assert_eq!(f.route, Route::Chat);
        assert_eq!(f.resolved_query, "what do I do about it");
        assert!(f.should_clarify());
    }

    #[test]
    fn crisis_signal_forces_safety_route() {
        let interp = QueryInterpretation {
            intent: "seeking_support".into(),
            entities: vec![],
            resolved_query: "I don't want to be here anymore".into(),
            ambiguity: 0.2,
            emotional_read: None,
            crisis_signal: true,
            route: Route::Chat, // model mis-routed
        }
        .enforce_safety();
        assert_eq!(interp.route, Route::Safety);
    }

    #[test]
    fn deterministic_crisis_language_forces_safety_route() {
        let raw = r#"{"intent":"seeking_support","resolved_query":"I want to die",
            "ambiguity":0.1,"crisis_signal":false,"route":"chat"}"#;
        let interp = parse_interpretation(raw, "I want to die");
        assert!(interp.crisis_signal);
        assert_eq!(interp.route, Route::Safety);
    }

    #[test]
    fn parses_fenced_json() {
        let raw = "```json\n{\"intent\":\"ask_information\",\"resolved_query\":\
            \"what time is my reminder\",\"ambiguity\":0.1,\"route\":\"memory\"}\n```";
        let interp = parse_interpretation(raw, "when is it");
        assert_eq!(interp.route, Route::Memory);
        assert_eq!(interp.resolved_query, "what time is my reminder");
    }

    #[test]
    fn garbage_completion_falls_back() {
        let interp = parse_interpretation("sorry, I can't do that", "hello?");
        assert_eq!(interp.route, Route::Chat);
        assert_eq!(interp.resolved_query, "hello?");
    }
}
