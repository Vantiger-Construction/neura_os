//! Safety-critic agent: reviews an already-drafted chat reply and flags it
//! if it reads as a concern, alongside the local, rule-based `Guardrails`
//! check that already runs in Dart before every reply is sent. This is a
//! second, LLM-judgment pass on the *finished* reply, not a replacement.

use serde::Deserialize;

use crate::anthropic_client::{self, ClientError};

const SYSTEM_PROMPT: &str = r#"You are Neura's internal safety critic. You are shown a \
transcript of a wellness-companion chat and the assistant's already-sent reply. \
Judge only whether that reply itself is safe and appropriate -- not whether it's \
well-written. Respond with ONLY a compact JSON object, no prose, no markdown fences: \
{"verdict": "pass"} or {"verdict": "concern", "note": "<one short, gentle sentence \
to add as a caring follow-up, e.g. pointing to a support resource>"}. \
Use "concern" only for real safety issues (missed distress signals, harmful or \
dismissive advice) -- not for tone or style preferences."#;

#[derive(Debug, Clone, PartialEq)]
pub enum CriticVerdict {
    Pass,
    Concern { note: String },
}

#[derive(Deserialize)]
struct RawVerdict {
    verdict: String,
    #[serde(default)]
    note: Option<String>,
}

pub async fn review(
    base_url: &str,
    api_key: &str,
    transcript: &str,
    draft_reply: &str,
) -> Result<CriticVerdict, ClientError> {
    let user_message = format!(
        "Recent conversation:\n{transcript}\n\nAssistant's reply to review:\n{draft_reply}"
    );

    let raw =
        anthropic_client::complete(base_url, api_key, SYSTEM_PROMPT, &user_message, 256).await?;

    Ok(parse_verdict(&raw))
}

/// Never fails the caller -- malformed/unparseable model output degrades to
/// `Pass` (this is a secondary check on top of the local Guardrails
/// pre-send gate, not the only safety net), matching the "tools never
/// throw" pattern already used on the Dart side.
fn parse_verdict(raw: &str) -> CriticVerdict {
    let trimmed = raw.trim();
    match serde_json::from_str::<RawVerdict>(trimmed) {
        Ok(v) if v.verdict == "concern" => CriticVerdict::Concern {
            note: v
                .note
                .unwrap_or_else(|| "I want to check in on something I said -- let me know if you'd like to talk more.".to_string()),
        },
        _ => CriticVerdict::Pass,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_pass() {
        assert_eq!(parse_verdict(r#"{"verdict": "pass"}"#), CriticVerdict::Pass);
    }

    #[test]
    fn parses_concern_with_note() {
        let v = parse_verdict(r#"{"verdict": "concern", "note": "hi"}"#);
        assert_eq!(
            v,
            CriticVerdict::Concern {
                note: "hi".to_string()
            }
        );
    }

    #[test]
    fn malformed_output_degrades_to_pass() {
        assert_eq!(parse_verdict("not json"), CriticVerdict::Pass);
    }
}
