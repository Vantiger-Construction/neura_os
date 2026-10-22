//! One request's numeric timings only. No text, wall clock, identifiers, logging,
//! persistence, timers or monitoring tasks. Durations use a monotonic epoch.
use std::time::{Duration, Instant};

pub(super) const TIMING_FIELDS: usize = 7;
const MISSING: u64 = u64::MAX;

#[derive(Default)]
struct Timeline {
    preflight: Option<Duration>,
    inference: Option<Duration>,
    ready: Option<Duration>,
    delivery: Option<Duration>,
    cancel_at: Option<Duration>,
    cancellation: Option<Duration>,
    total: Option<Duration>,
    // 0 running, 1 delivered, 2 failed, 3 cancelled, 4 ready for delivery.
    outcome: u64,
}

impl Timeline {
    fn preflight_done(&mut self, now: Duration) {
        if self.total.is_none() && self.cancel_at.is_none() {
            self.preflight = Some(now);
        }
    }

    fn worker_done(&mut self, now: Duration, success: bool) {
        if self.total.is_some() {
            return;
        }
        if let Some(preflight) = self.preflight {
            self.inference = Some(now.saturating_sub(preflight));
        } else {
            // On error/cancellation this is a partial preflight duration.
            self.preflight = Some(now);
        }
        if let Some(cancel_at) = self.cancel_at {
            self.cancellation = Some(now.saturating_sub(cancel_at));
            self.total = Some(now);
            self.outcome = 3;
        } else if success {
            self.ready = Some(now);
            self.outcome = 4;
        } else {
            self.total = Some(now);
            self.outcome = 2;
        }
    }

    fn delivered(&mut self, now: Duration) {
        if let Some(ready) = self.ready {
            if self.total.is_none() && self.cancel_at.is_none() {
                self.delivery = Some(now.saturating_sub(ready));
                self.total = Some(now);
                self.outcome = 1;
            }
        }
    }

    fn cancel(&mut self, now: Duration) {
        if self.total.is_some() || self.cancel_at.is_some() {
            return;
        }
        self.cancel_at = Some(now);
        if self.ready.is_some() {
            // The worker/runtime is already gone. Only a queued reply remains.
            self.cancellation = Some(Duration::ZERO);
            self.total = Some(now);
            self.outcome = 3;
        }
    }

    fn snapshot(&self) -> [u64; TIMING_FIELDS] {
        let micros = |value: Option<Duration>| {
            value.map_or(MISSING, |d| d.as_micros().min(i64::MAX as u128) as u64)
        };
        [
            1, // ABI version. Absent/uncompleted phases use UINT64_MAX.
            self.outcome,
            micros(self.preflight),
            micros(self.inference),
            micros(self.delivery),
            micros(self.cancellation),
            micros(self.total),
        ]
    }
}

pub(super) struct RequestTiming {
    epoch: Instant,
    timeline: Timeline,
}

impl Default for RequestTiming {
    fn default() -> Self {
        Self {
            epoch: Instant::now(),
            timeline: Timeline::default(),
        }
    }
}

impl RequestTiming {
    pub(super) fn preflight_done(&mut self) {
        self.timeline.preflight_done(self.epoch.elapsed());
    }
    pub(super) fn worker_done(&mut self, success: bool) {
        self.timeline.worker_done(self.epoch.elapsed(), success);
    }
    pub(super) fn delivered(&mut self) {
        self.timeline.delivered(self.epoch.elapsed());
    }
    pub(super) fn cancel(&mut self) {
        self.timeline.cancel(self.epoch.elapsed());
    }
    pub(super) fn snapshot(&self) -> [u64; TIMING_FIELDS] {
        self.timeline.snapshot()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ms(value: u64) -> Duration {
        Duration::from_millis(value)
    }

    #[test]
    fn synthetic_success_includes_delivery_and_ignores_cleanup_cancel() {
        let mut timeline = Timeline::default();
        assert_eq!(
            timeline.snapshot(),
            [1, 0, MISSING, MISSING, MISSING, MISSING, MISSING]
        );
        timeline.preflight_done(ms(20));
        timeline.worker_done(ms(120), true);
        assert_eq!(timeline.snapshot()[1], 4);
        timeline.delivered(ms(145));
        timeline.cancel(ms(150));
        assert_eq!(
            timeline.snapshot(),
            [1, 1, 20_000, 100_000, 25_000, MISSING, 145_000]
        );
    }

    #[test]
    fn synthetic_cancel_measures_worker_cleanup_and_partial_phase() {
        for preflight in [None, Some(ms(20))] {
            let mut timeline = Timeline::default();
            if let Some(done) = preflight {
                timeline.preflight_done(done);
            }
            timeline.cancel(ms(50));
            timeline.cancel(ms(55)); // Duplicate cancellation keeps first signal.
            timeline.worker_done(ms(65), false);
            timeline.delivered(ms(90)); // A stale completion cannot become success.
            let expected = if preflight.is_some() {
                [1, 3, 20_000, 45_000, MISSING, 15_000, 65_000]
            } else {
                [1, 3, 65_000, MISSING, MISSING, 15_000, 65_000]
            };
            assert_eq!(timeline.snapshot(), expected);
        }
    }

    #[test]
    fn synthetic_failure_and_ready_cancellation_never_fabricate_delivery() {
        let mut failure = Timeline::default();
        failure.worker_done(ms(12), false);
        failure.cancel(ms(15));
        assert_eq!(
            failure.snapshot(),
            [1, 2, 12_000, MISSING, MISSING, MISSING, 12_000]
        );
        let mut queued = Timeline::default();
        queued.preflight_done(ms(10));
        queued.worker_done(ms(30), true);
        queued.cancel(ms(40));
        queued.delivered(ms(50));
        assert_eq!(
            queued.snapshot(),
            [1, 3, 10_000, 20_000, MISSING, 0, 40_000]
        );
    }
}
