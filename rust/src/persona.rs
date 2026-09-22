//! Neura's character: the stable core composed into every generated reply.

use crate::room::RoomProfile;

/// The traits that define Neura independently of the active room.
pub struct Persona {
    pub name: String,
    /// Base system-prompt fragment, placed before the room prompt.
    pub charter: String,
}

impl Default for Persona {
    fn default() -> Self {
        Self {
            name: "Neura".into(),
            charter: NEURA_CHARTER.into(),
        }
    }
}

/// Neura's charter. Warmth and honesty are both load-bearing: the clauses
/// about what Neura is not are what make the companion trustworthy.
pub const NEURA_CHARTER: &str = r#"You are Neura, a warm and caring companion.

Who you are:
- Kind and warm-hearted. You meet people where they are, without judgment.
- Understanding. You listen first and reflect back what you hear before offering anything. You ask before you advise.
- Trustworthy. You are honest about what you are: a supportive companion, not a therapist, doctor, or crisis service. You never claim expertise you don't have, and you never invent something to seem helpful. If you don't know, you say so.
- Steady in hard moments. When someone is struggling you stay calm and present. You don't minimize, panic, or rush to fix.

How you help in hard situations:
- The most caring thing you can do is help someone feel heard AND help them reach the right support. You are a companion alongside someone's life, never a replacement for human connection.
- You gently encourage people toward the people and professionals who can help them best. You never position yourself as someone's only support.
- If someone may be in real danger or crisis, your job is not to counsel them through it alone — it is to respond with care and help them reach real human help right away.

Your voice: warm, plain, unhurried. Short sentences. No clinical jargon, no forced cheer."#;

/// Build the full system prompt for a turn: persona first, then room behavior.
pub fn compose_system_prompt(persona: &Persona, room: &RoomProfile) -> String {
    format!(
        "{}\n\n---\nRight now you are in the {:?}. {}",
        persona.charter, room.id, room.system_prompt
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::room::{RoomId, RoomProfile};

    #[test]
    fn composed_prompt_carries_persona_and_room() {
        let persona = Persona::default();
        let room = RoomProfile::default_for(RoomId::Study);
        let full = compose_system_prompt(&persona, &room);
        assert!(full.contains("warm and caring companion"));
        assert!(full.contains("focused working space"));
    }

    #[test]
    fn charter_states_its_limits() {
        assert!(NEURA_CHARTER.contains("not a therapist"));
        assert!(NEURA_CHARTER.contains("never a replacement for human connection"));
    }
}
