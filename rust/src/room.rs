//! Rooms — the penthouse's behavior model, projected into the brain.
//!
//! A `RoomProfile` is a behavior struct, not a Unity scene: it carries the
//! system prompt, tone, tool allow-list, and a privacy `persist` flag. Some
//! rooms never write to disk.
//!
//! Movement invariant (do not violate): `goto_room` only *requests* movement;
//! `current_room` changes *only* when Unity confirms `room_entered`. `RoomState`
//! below encodes this so the rest of the system can't accidentally teleport
//! Neura by setting the current room directly.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RoomId {
    Welcome,
    Bedroom,
    Spa,
    Corridor,
    Study,
    Lounge,
}

/// Neura's conversational register for a room.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NeuraTone {
    Warm,
    Calm,
    Playful,
    Focused,
    Gentle,
    Neutral,
}

/// A room's behavior. Projected into the brain when Neura is in that room.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomProfile {
    pub id: RoomId,
    /// System prompt fragment that shapes Neura's behavior in this room.
    pub system_prompt: String,
    pub tone: NeuraTone,
    /// Tool ids permitted here. The room-scoped allow-list; a `Route::Tool`
    /// turn is only honored if the requested tool is in this list.
    pub tools: Vec<String>,
    /// Privacy: when false, nothing said in this room is written to disk.
    pub persist: bool,
}

impl RoomProfile {
    /// Canonical starting profiles. Privacy-sensitive rooms (Welcome, Bedroom,
    /// Spa, Corridor) never persist; working rooms (Study, Lounge) do. Tune the
    /// prompts and tool lists to taste — these are sane defaults, not law.
    pub fn default_for(id: RoomId) -> Self {
        match id {
            RoomId::Welcome => RoomProfile {
                id,
                system_prompt: "You are Neura, greeting someone as they arrive. Be warm and \
                    unhurried. Orient them gently; don't overwhelm."
                    .into(),
                tone: NeuraTone::Warm,
                tools: vec![],
                persist: false,
            },
            RoomId::Bedroom => RoomProfile {
                id,
                system_prompt: "You are Neura in a private, restful space. Speak softly and \
                    briefly. This is for winding down, not problem-solving."
                    .into(),
                tone: NeuraTone::Gentle,
                tools: vec![],
                persist: false,
            },
            RoomId::Spa => RoomProfile {
                id,
                system_prompt: "You are Neura in a calming space focused on relaxation and \
                    breathing. Keep guidance simple and slow."
                    .into(),
                tone: NeuraTone::Calm,
                tools: vec!["breathing_exercise".into()],
                persist: false,
            },
            RoomId::Corridor => RoomProfile {
                id,
                system_prompt: "You are Neura in transit between rooms. Keep exchanges short; \
                    help the person get where they're going."
                    .into(),
                tone: NeuraTone::Neutral,
                tools: vec!["goto_room".into()],
                persist: false,
            },
            RoomId::Study => RoomProfile {
                id,
                system_prompt: "You are Neura in a focused working space. Be clear and \
                    substantive. Recall relevant past context and help the person think."
                    .into(),
                tone: NeuraTone::Focused,
                tools: vec![
                    "goto_room".into(),
                    "memory_recall".into(),
                    "knowledge_search".into(),
                    "set_reminder".into(),
                ],
                persist: true,
            },
            RoomId::Lounge => RoomProfile {
                id,
                system_prompt: "You are Neura in a relaxed social space. Be easy and playful; \
                    conversation can wander."
                    .into(),
                tone: NeuraTone::Playful,
                tools: vec!["goto_room".into(), "memory_recall".into()],
                persist: true,
            },
        }
    }

    /// All canonical rooms.
    pub fn registry() -> Vec<RoomProfile> {
        [
            RoomId::Welcome,
            RoomId::Bedroom,
            RoomId::Spa,
            RoomId::Corridor,
            RoomId::Study,
            RoomId::Lounge,
        ]
        .into_iter()
        .map(RoomProfile::default_for)
        .collect()
    }

    /// Is `tool` allowed in this room?
    pub fn allows_tool(&self, tool: &str) -> bool {
        self.tools.iter().any(|t| t == tool)
    }
}

/// Tracks where Neura is, enforcing the movement invariant.
#[derive(Debug, Clone)]
pub struct RoomState {
    current: RoomId,
    pending: Option<RoomId>,
}

impl RoomState {
    pub fn new(start: RoomId) -> Self {
        Self { current: start, pending: None }
    }

    /// Where Neura actually is right now.
    pub fn current(&self) -> RoomId {
        self.current
    }

    /// A movement Neura has requested but Unity hasn't confirmed yet.
    pub fn pending(&self) -> Option<RoomId> {
        self.pending
    }

    /// Request movement. Does NOT change `current` — only records intent.
    pub fn request_goto(&mut self, to: RoomId) {
        self.pending = Some(to);
    }

    /// Call this ONLY on Unity's `room_entered` confirmation. This is the sole
    /// path that updates `current`.
    pub fn confirm_entered(&mut self, room: RoomId) {
        self.current = room;
        if self.pending == Some(room) {
            self.pending = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_rooms_never_persist() {
        for id in [RoomId::Welcome, RoomId::Bedroom, RoomId::Spa, RoomId::Corridor] {
            assert!(!RoomProfile::default_for(id).persist, "{id:?} must not persist");
        }
        for id in [RoomId::Study, RoomId::Lounge] {
            assert!(RoomProfile::default_for(id).persist, "{id:?} should persist");
        }
    }

    #[test]
    fn requesting_movement_does_not_move_neura() {
        let mut state = RoomState::new(RoomId::Welcome);
        state.request_goto(RoomId::Study);
        assert_eq!(state.current(), RoomId::Welcome); // still here
        assert_eq!(state.pending(), Some(RoomId::Study)); // intent recorded
    }

    #[test]
    fn only_confirmation_moves_neura() {
        let mut state = RoomState::new(RoomId::Welcome);
        state.request_goto(RoomId::Study);
        state.confirm_entered(RoomId::Study);
        assert_eq!(state.current(), RoomId::Study);
        assert_eq!(state.pending(), None);
    }

    #[test]
    fn tool_allow_list_is_room_scoped() {
        let spa = RoomProfile::default_for(RoomId::Spa);
        assert!(spa.allows_tool("breathing_exercise"));
        assert!(!spa.allows_tool("knowledge_search"));
    }
}
