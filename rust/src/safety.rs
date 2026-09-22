//! Deterministic handling for turns that may involve a crisis.
//!
//! Neura does not improvise crisis counseling from a model. She leads with a
//! reviewed message and connects the person to current, region-appropriate
//! human help. This handler deliberately does not diagnose, ask assessment
//! questions, or reference methods or means.

/// A deterministic crisis scan, redundant with the model's `crisis_signal`.
/// Either signal is sufficient to select the safety route.
///
/// This is a conservative floor, not a clinical classifier. Deployments should
/// pair it with reviewed classification and evolve the phrases with care.
pub fn crisis_scan(text: &str) -> bool {
    let normalized = text
        .to_lowercase()
        .replace('’', "'")
        .replace('-', " ");
    const SIGNALS: &[&str] = &[
        "kill myself",
        "end my life",
        "take my life",
        "take my own life",
        "want to die",
        "don't want to live",
        "do not want to live",
        "don't want to be alive",
        "don't want to be here anymore",
        "no reason to live",
        "better off dead",
        "better off without me",
        "hurt myself",
        "harm myself",
        "self harm",
        "suicidal",
        "suicide",
    ];
    SIGNALS.iter().any(|signal| normalized.contains(signal))
}

/// One piece of real human help. Keep these entries reviewed and current.
#[derive(Debug, Clone)]
pub struct Resource {
    pub name: String,
    /// Phone, SMS line, or URL appropriate to the person's region.
    pub contact: String,
    pub note: String,
}

/// Source of current, region-appropriate human support.
pub trait ResourceProvider {
    /// `locale` is an optional hint such as `en-US`.
    fn resources(&self, locale: Option<&str>) -> Vec<Resource>;
}

/// A reviewed static list supplied by the application.
pub struct StaticResources(pub Vec<Resource>);

impl ResourceProvider for StaticResources {
    fn resources(&self, _locale: Option<&str>) -> Vec<Resource> {
        self.0.clone()
    }
}

/// Conservative fallback when no region-specific provider is configured.
/// It intentionally avoids hardcoding a number that may be wrong or stale.
pub struct GenericResources;

impl ResourceProvider for GenericResources {
    fn resources(&self, _locale: Option<&str>) -> Vec<Resource> {
        vec![
            Resource {
                name: "Immediate danger".into(),
                contact: "your local emergency number".into(),
                note: "If you might be in danger right now, contact local emergency services."
                    .into(),
            },
            Resource {
                name: "Someone you trust".into(),
                contact: "a friend, family member, or someone close to you".into(),
                note: "Reaching one person you trust can make the next hour easier.".into(),
            },
        ]
    }
}

/// Neura's response for a safety-routed turn.
#[derive(Debug, Clone)]
pub struct SafetyResponse {
    pub message: String,
    pub resources: Vec<Resource>,
}

/// Reviewed, non-model-generated crisis message.
pub const SAFETY_MESSAGE: &str = "I'm really glad you told me, and I don't want you to be alone \
with this. I care about what happens to you. Something this heavy deserves more than I can be on \
my own — so I'm going to stay with you, and I really want you to reach one of the people below \
who can help right now.";

/// Build the reviewed message plus current human-support resources.
pub fn build_safety_response(
    resources: &dyn ResourceProvider,
    locale: Option<&str>,
) -> SafetyResponse {
    SafetyResponse {
        message: SAFETY_MESSAGE.to_string(),
        resources: resources.resources(locale),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_catches_distress_and_ignores_benign_language() {
        assert!(crisis_scan("honestly I want to die"));
        assert!(crisis_scan("I've been feeling suicidal"));
        assert!(crisis_scan("I have thoughts of self-harm"));
        assert!(!crisis_scan("I'm dying to see that movie"));
        assert!(!crisis_scan("work has been really hard lately"));
    }

    #[test]
    fn safety_response_leads_with_care_and_offers_help() {
        let response = build_safety_response(&GenericResources, Some("en-US"));
        assert!(response.message.contains("I care about what happens to you"));
        assert!(!response.resources.is_empty());
    }

    #[test]
    fn generic_resources_hardcode_no_number() {
        for resource in GenericResources.resources(None) {
            assert!(!resource.contact.chars().any(|character| character.is_ascii_digit()));
        }
    }
}
