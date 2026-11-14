//! Opt-in avatar presence relay for `neura_api`.
//!
//! One authorized publisher (the Neura app) sends the versioned, content-free
//! avatar presentation snapshot; any authorized subscriber (the Unity
//! presence prototype) receives the latest one. Both authenticate with the
//! process's existing session token, so the relay adds no new credential and
//! no new listener. It is disabled unless the trusted launcher sets
//! `NEURA_API_PRESENCE_RELAY=1`.
//!
//! Freshness: a publisher must republish at least every `ttl`. A subscriber
//! sees `avatar_presence_cleared` as soon as the publisher goes silent,
//! disconnects, clears, or sends an invalid snapshot, and the receiver falls
//! back to its safe Still presentation. The relay never stores history.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tokio::{sync::watch, time::Instant};

pub(crate) const PRESENCE_RELAY_ENV: &str = "NEURA_API_PRESENCE_RELAY";
/// A snapshot older than this is withdrawn from subscribers.
pub(crate) const PRESENCE_TTL: Duration = Duration::from_secs(6);
/// A live snapshot is re-sent at this interval so receivers can tell a quiet
/// but healthy link from a hung one.
pub(crate) const PRESENCE_KEEPALIVE: Duration = Duration::from_secs(2);

pub(crate) const KIND_PRESENCE: &str = "avatar_presence";
pub(crate) const KIND_CLEARED: &str = "avatar_presence_cleared";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Room {
    Penthouse,
    ReflectionBay,
    JoyLounge,
    MoodDen,
    DreamAtrium,
    LegacyVault,
    /// Neura's own room. Contract v2 only.
    HerSuite,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Phase {
    Idle,
    Thinking,
    Speaking,
    Listening,
    SafeMode,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Stance {
    Welcoming,
    Reflective,
    Playful,
    Grounding,
    Dreaming,
    Guardian,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Motion {
    Still,
    Subtle,
    Expressive,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Scale {
    Compact,
    Standard,
    Large,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Lighting {
    Standard,
    Gold,
    Aurora,
    Dusk,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Camera {
    Follow,
    Wide,
    Face,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Activity {
    Present,
    Resting,
}

/// Mirrors `prototypes/unity-presence/Contract/avatar-presence-v2.schema.json`
/// (and the earlier v1 schema) and the Dart `NeuraAvatarRuntimeSnapshot
/// .toJson()`. Unknown, duplicate or mistyped fields are rejected by serde;
/// [Snapshot::parse] then requires exactly the field set of the stated
/// version.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Snapshot {
    v: u32,
    room_id: Room,
    phase: Phase,
    stance: Stance,
    motion: Motion,
    scale: Scale,
    safe_mode: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    lighting: Option<Lighting>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    camera: Option<Camera>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    activity: Option<Activity>,
}

impl Snapshot {
    /// Parses and canonicalizes an untrusted snapshot. v1 has the original
    /// seven fields and can't name `her_suite`; v2 adds `lighting`, `camera`
    /// and `activity`, all required. Either Safe Mode signal forces Safe
    /// Mode, the safeMode phase, Still motion and (in v2) the present pose.
    pub(crate) fn parse(data: Value) -> Option<Self> {
        let mut snapshot: Snapshot = serde_json::from_value(data).ok()?;
        let stage = (snapshot.lighting, snapshot.camera, snapshot.activity);
        match snapshot.v {
            1 => {
                if stage != (None, None, None) || snapshot.room_id == Room::HerSuite {
                    return None;
                }
            }
            2 => {
                if stage.0.is_none() || stage.1.is_none() || stage.2.is_none() {
                    return None;
                }
            }
            _ => return None,
        }
        if snapshot.safe_mode || snapshot.phase == Phase::SafeMode {
            snapshot.safe_mode = true;
            snapshot.phase = Phase::SafeMode;
            snapshot.motion = Motion::Still;
            if snapshot.activity.is_some() {
                snapshot.activity = Some(Activity::Present);
            }
        }
        Some(snapshot)
    }

    pub(crate) fn to_value(self) -> Value {
        serde_json::to_value(self).expect("serialize presence snapshot")
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Published {
    None,
    Live { snapshot: Snapshot, at: Instant },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ClearReason {
    NoPublisher,
    Stale,
}

impl ClearReason {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::NoPublisher => "no_publisher",
            Self::Stale => "stale",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Delivery {
    Presence(Snapshot),
    Cleared(ClearReason),
}

#[derive(Clone)]
pub(crate) struct PresenceHub {
    state: watch::Sender<Published>,
    publisher: Arc<Mutex<Option<u64>>>,
    next_id: Arc<AtomicU64>,
    pub(crate) ttl: Duration,
    pub(crate) keepalive: Duration,
}

impl PresenceHub {
    pub(crate) fn new(ttl: Duration, keepalive: Duration) -> Self {
        let (state, _) = watch::channel(Published::None);
        Self {
            state,
            publisher: Arc::new(Mutex::new(None)),
            next_id: Arc::new(AtomicU64::new(1)),
            ttl,
            keepalive,
        }
    }

    /// Reads the launcher setting. Absent means disabled; only `1` enables;
    /// anything else fails closed without echoing the value.
    pub(crate) fn from_env_setting(
        value: Result<String, std::env::VarError>,
    ) -> Result<Option<Self>, &'static str> {
        match value {
            Err(std::env::VarError::NotPresent) => Ok(None),
            Ok(value) if value == "1" => Ok(Some(Self::new(PRESENCE_TTL, PRESENCE_KEEPALIVE))),
            _ => Err("NEURA_API_PRESENCE_RELAY must be 1 when set"),
        }
    }

    pub(crate) fn subscribe(&self) -> watch::Receiver<Published> {
        self.state.subscribe()
    }

    /// Claims the single publisher slot, or `None` while another holds it.
    pub(crate) fn claim(&self) -> Option<PublisherGuard> {
        let mut slot = self.publisher.lock().unwrap_or_else(|p| p.into_inner());
        if slot.is_some() {
            return None;
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        *slot = Some(id);
        Some(PublisherGuard {
            hub: self.clone(),
            id,
        })
    }

    fn owns(&self, id: u64) -> bool {
        *self.publisher.lock().unwrap_or_else(|p| p.into_inner()) == Some(id)
    }
}

/// Holds the publisher slot. Dropping it (publisher disconnect, revocation
/// or any connection teardown) withdraws the published snapshot.
pub(crate) struct PublisherGuard {
    hub: PresenceHub,
    id: u64,
}

impl PublisherGuard {
    pub(crate) fn publish(&self, snapshot: Snapshot) {
        if self.hub.owns(self.id) {
            self.hub.state.send_replace(Published::Live {
                snapshot,
                at: Instant::now(),
            });
        }
    }

    pub(crate) fn clear(&self) {
        if self.hub.owns(self.id) {
            self.hub.state.send_replace(Published::None);
        }
    }
}

impl Drop for PublisherGuard {
    fn drop(&mut self) {
        let mut slot = self.hub.publisher.lock().unwrap_or_else(|p| p.into_inner());
        if *slot == Some(self.id) {
            *slot = None;
            self.hub.state.send_replace(Published::None);
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Shown {
    Nothing,
    Presence(Snapshot),
    Cleared,
}

/// What one subscriber has been told. Pure, so the delivery rules are
/// unit-testable without sockets or real time.
#[derive(Clone, Copy, Debug)]
pub(crate) struct SubscriberView {
    shown: Shown,
    last_sent: Option<Instant>,
    ttl: Duration,
    keepalive: Duration,
}

impl SubscriberView {
    pub(crate) fn new(ttl: Duration, keepalive: Duration) -> Self {
        Self {
            shown: Shown::Nothing,
            last_sent: None,
            ttl,
            keepalive,
        }
    }

    /// Forget what was shown, so the next evaluation re-sends the current
    /// state (receiver resync after it suspended its presentation).
    pub(crate) fn reset(&mut self) {
        self.shown = Shown::Nothing;
        self.last_sent = None;
    }

    pub(crate) fn next(&mut self, published: Published, now: Instant) -> Option<Delivery> {
        let delivery = match published {
            Published::None => Delivery::Cleared(ClearReason::NoPublisher),
            Published::Live { at, .. } if now.saturating_duration_since(at) >= self.ttl => {
                Delivery::Cleared(ClearReason::Stale)
            }
            Published::Live { snapshot, .. } => Delivery::Presence(snapshot),
        };
        let due = match (delivery, self.shown) {
            (Delivery::Cleared(_), Shown::Cleared) => false,
            (Delivery::Cleared(_), _) => true,
            (Delivery::Presence(snapshot), Shown::Presence(shown)) if snapshot == shown => self
                .last_sent
                .is_none_or(|sent| now.saturating_duration_since(sent) >= self.keepalive),
            (Delivery::Presence(_), _) => true,
        };
        if !due {
            return None;
        }
        self.shown = match delivery {
            Delivery::Presence(snapshot) => Shown::Presence(snapshot),
            Delivery::Cleared(_) => Shown::Cleared,
        };
        self.last_sent = Some(now);
        Some(delivery)
    }

    /// When this view must next be re-evaluated without any hub change:
    /// the staleness deadline or the keepalive, whichever is first.
    pub(crate) fn deadline(&self, published: Published) -> Option<Instant> {
        let (Published::Live { at, .. }, Shown::Presence(_)) = (published, self.shown) else {
            return None;
        };
        let stale = at + self.ttl;
        Some(match self.last_sent {
            Some(sent) => stale.min(sent + self.keepalive),
            None => stale,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn valid() -> Value {
        json!({"v":1,"room_id":"reflection_bay","phase":"thinking","stance":"reflective",
               "motion":"subtle","scale":"standard","safe_mode":false})
    }

    fn with(key: &str, value: Value) -> Value {
        let mut data = valid();
        data[key] = value;
        data
    }

    #[test]
    fn parses_the_full_v1_domain() {
        assert!(Snapshot::parse(valid()).is_some());
        for room in [
            "penthouse",
            "reflection_bay",
            "joy_lounge",
            "mood_den",
            "dream_atrium",
            "legacy_vault",
        ] {
            assert!(
                Snapshot::parse(with("room_id", json!(room))).is_some(),
                "{room}"
            );
        }
        for phase in ["idle", "thinking", "speaking", "listening", "safeMode"] {
            assert!(
                Snapshot::parse(with("phase", json!(phase))).is_some(),
                "{phase}"
            );
        }
        for stance in [
            "welcoming",
            "reflective",
            "playful",
            "grounding",
            "dreaming",
            "guardian",
        ] {
            assert!(
                Snapshot::parse(with("stance", json!(stance))).is_some(),
                "{stance}"
            );
        }
    }

    #[test]
    fn rejects_unknown_missing_mistyped_and_future_input() {
        let mut extra = valid();
        extra["journal"] = json!("private");
        assert!(Snapshot::parse(extra).is_none());
        let mut missing = valid();
        missing.as_object_mut().unwrap().remove("scale");
        assert!(Snapshot::parse(missing).is_none());
        assert!(Snapshot::parse(with("v", json!(3))).is_none());
        // v2 without its stage fields, and v1 with them, are both rejected.
        assert!(Snapshot::parse(with("v", json!(2))).is_none());
        let mut v1_with_stage = valid();
        v1_with_stage["lighting"] = json!("gold");
        assert!(Snapshot::parse(v1_with_stage).is_none());
        assert!(Snapshot::parse(with("room_id", json!("her_suite"))).is_none());
        assert!(Snapshot::parse(with("room_id", json!("bedroom"))).is_none());
        assert!(Snapshot::parse(with("phase", json!("safe_mode"))).is_none());
        assert!(Snapshot::parse(with("safe_mode", json!("false"))).is_none());
        assert!(Snapshot::parse(json!("not an object")).is_none());
    }

    fn valid_v2() -> Value {
        json!({"v":2,"room_id":"her_suite","phase":"idle","stance":"welcoming",
               "motion":"subtle","scale":"standard","safe_mode":false,
               "lighting":"gold","camera":"follow","activity":"resting"})
    }

    #[test]
    fn parses_the_full_v2_domain_and_round_trips() {
        let parsed = Snapshot::parse(valid_v2()).unwrap();
        assert_eq!(parsed.to_value(), valid_v2());
        for room in ["penthouse", "legacy_vault", "her_suite"] {
            let mut data = valid_v2();
            data["room_id"] = json!(room);
            assert!(Snapshot::parse(data).is_some(), "{room}");
        }
        for (key, values) in [
            ("lighting", &["standard", "gold", "aurora", "dusk"][..]),
            ("camera", &["follow", "wide", "face"][..]),
            ("activity", &["present", "resting"][..]),
        ] {
            for value in values {
                let mut data = valid_v2();
                data[key] = json!(value);
                assert!(Snapshot::parse(data).is_some(), "{key}={value}");
            }
        }
        // v1 output keeps exactly the v1 shape.
        let v1 = Snapshot::parse(valid()).unwrap().to_value();
        assert_eq!(v1, valid());
    }

    #[test]
    fn rejects_incomplete_or_unknown_v2_input() {
        for key in ["lighting", "camera", "activity"] {
            let mut missing = valid_v2();
            missing.as_object_mut().unwrap().remove(key);
            assert!(Snapshot::parse(missing).is_none(), "{key}");
        }
        for (key, value) in [
            ("lighting", "neon"),
            ("camera", "orbit"),
            ("activity", "sleeping"),
        ] {
            let mut data = valid_v2();
            data[key] = json!(value);
            assert!(Snapshot::parse(data).is_none(), "{key}={value}");
        }
        let mut extra = valid_v2();
        extra["memory"] = json!("private");
        assert!(Snapshot::parse(extra).is_none());
    }

    #[test]
    fn safe_mode_in_v2_forces_the_present_still_pose() {
        let mut data = valid_v2();
        data["safe_mode"] = json!(true);
        data["motion"] = json!("expressive");
        let value = Snapshot::parse(data).unwrap().to_value();
        assert_eq!(value["phase"], "safeMode");
        assert_eq!(value["motion"], "still");
        assert_eq!(value["activity"], "present");
        assert_eq!(value["lighting"], "gold");
    }

    #[test]
    fn either_safe_signal_forces_safe_still() {
        for data in [
            with("safe_mode", json!(true)),
            with("phase", json!("safeMode")),
        ] {
            let mut data = data;
            data["motion"] = json!("expressive");
            let value = Snapshot::parse(data).unwrap().to_value();
            assert_eq!(value["safe_mode"], true);
            assert_eq!(value["phase"], "safeMode");
            assert_eq!(value["motion"], "still");
        }
    }

    #[test]
    fn env_setting_is_off_by_default_and_fails_closed() {
        assert!(
            PresenceHub::from_env_setting(Err(std::env::VarError::NotPresent))
                .unwrap()
                .is_none()
        );
        assert!(PresenceHub::from_env_setting(Ok("1".into()))
            .unwrap()
            .is_some());
        for value in ["0", "true", "yes", ""] {
            assert!(
                PresenceHub::from_env_setting(Ok(value.into())).is_err(),
                "{value}"
            );
        }
    }

    #[tokio::test]
    async fn single_publisher_and_drop_withdraws_presence() {
        let hub = PresenceHub::new(PRESENCE_TTL, PRESENCE_KEEPALIVE);
        let rx = hub.subscribe();
        let first = hub.claim().unwrap();
        assert!(hub.claim().is_none());
        first.publish(Snapshot::parse(valid()).unwrap());
        assert!(matches!(*rx.borrow(), Published::Live { .. }));
        drop(first);
        assert_eq!(*rx.borrow(), Published::None);
        assert!(hub.claim().is_some());
    }

    #[test]
    fn view_coalesces_keepalives_and_withdraws_stale_or_missing_presence() {
        let ttl = Duration::from_secs(6);
        let keepalive = Duration::from_secs(2);
        let mut view = SubscriberView::new(ttl, keepalive);
        let t0 = Instant::now();
        let snap = Snapshot::parse(valid()).unwrap();

        assert_eq!(
            view.next(Published::None, t0),
            Some(Delivery::Cleared(ClearReason::NoPublisher))
        );
        assert_eq!(view.next(Published::None, t0), None);

        let live = Published::Live {
            snapshot: snap,
            at: t0,
        };
        assert_eq!(view.next(live, t0), Some(Delivery::Presence(snap)));
        // A heartbeat with an unchanged snapshot is coalesced...
        let heartbeat = Published::Live {
            snapshot: snap,
            at: t0 + Duration::from_millis(500),
        };
        assert_eq!(view.next(heartbeat, t0 + Duration::from_millis(500)), None);
        // ...until the keepalive interval, when it is re-sent.
        assert_eq!(view.deadline(heartbeat), Some(t0 + keepalive));
        assert_eq!(
            view.next(heartbeat, t0 + keepalive),
            Some(Delivery::Presence(snap))
        );

        // A changed snapshot is sent at once.
        let changed = Snapshot::parse(with("phase", json!("speaking"))).unwrap();
        let live2 = Published::Live {
            snapshot: changed,
            at: t0 + keepalive,
        };
        assert_eq!(
            view.next(live2, t0 + keepalive),
            Some(Delivery::Presence(changed))
        );

        // A silent publisher goes stale exactly once.
        let late = t0 + keepalive + ttl;
        assert_eq!(
            view.next(live2, late),
            Some(Delivery::Cleared(ClearReason::Stale))
        );
        assert_eq!(view.next(live2, late + keepalive), None);
        assert_eq!(view.deadline(live2), None);
    }

    #[test]
    fn reset_resends_the_current_state() {
        let mut view = SubscriberView::new(PRESENCE_TTL, PRESENCE_KEEPALIVE);
        let t0 = Instant::now();
        let snap = Snapshot::parse(valid()).unwrap();
        let live = Published::Live {
            snapshot: snap,
            at: t0,
        };
        assert!(view.next(live, t0).is_some());
        assert!(view.next(live, t0).is_none());
        view.reset();
        assert_eq!(view.next(live, t0), Some(Delivery::Presence(snap)));
    }
}
