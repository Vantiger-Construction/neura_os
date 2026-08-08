//! Memory-extraction agent: pulls durable facts worth remembering out of a
//! chat turn. Extraction only -- persistence stays in Dart via the existing
//! `MemoryGraphService.I.logUserAction` append-only encrypted store, so this
//! agent never touches disk.

use serde::Deserialize;

use crate::anthropic_client::{self, ClientError};

const SYSTEM_PROMPT: &str = r#"You are Neura's internal memory extractor. You are shown \
one chat exchange (user message and assistant reply). Extract only durable facts worth \
remembering long-term about the user (preferences, people/relationships they mention, \
ongoing goals or struggles, important dates) -- not small talk or the assistant's own \
reply content. Respond with ONLY a compact JSON array, no prose, no markdown fences: \
[{"summary": "<short fact, third person, e.g. 'Prefers evening walks over gym visits'>", \
"kind": "<one short category word, e.g. preference, relationship, goal, event>"}]. \
Return [] if nothing durable is worth remembering from this exchange."#;

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct MemoryFact {
    pub summary: String,
    pub kind: String,
}

pub async fn extract(
    base_url: &str,
    api_key: &str,
    user_message: &str,
    assistant_reply: &str,
) -> Result<Vec<MemoryFact>, ClientError> {
    let prompt = format!("User: {user_message}\nAssistant: {assistant_reply}");

    let raw = anthropic_client::complete(base_url, api_key, SYSTEM_PROMPT, &prompt, 512).await?;

    Ok(parse_facts(&raw))
}

/// Never fails the caller -- malformed output just means no facts extracted
/// this turn, same "degrade gracefully" pattern as the critic agent.
fn parse_facts(raw: &str) -> Vec<MemoryFact> {
    serde_json::from_str::<Vec<MemoryFact>>(raw.trim()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_facts() {
        let facts = parse_facts(r#"[{"summary": "Likes tea", "kind": "preference"}]"#);
        assert_eq!(
            facts,
            vec![MemoryFact {
                summary: "Likes tea".to_string(),
                kind: "preference".to_string()
            }]
        );
    }

    #[test]
    fn empty_array_is_no_facts() {
        assert_eq!(parse_facts("[]"), Vec::<MemoryFact>::new());
    }

    #[test]
    fn malformed_output_degrades_to_empty() {
        assert_eq!(parse_facts("not json"), Vec::<MemoryFact>::new());
    }
}
