//! Bounded, in-memory scoring of binary forecasts, with no runtime wiring.
//!
//! Forecasts are immutable after admission. Opaque identifiers are unique within
//! this loaded library instance; neither clearing nor forgetting reuses them.
//! They are not durable IDs or authorization tokens. See
//! `docs/FORECAST_CALIBRATION_FOUNDATION.md` for ownership and integration limits.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};

pub const MAX_OPEN: usize = 256;
pub const MAX_SCORED: usize = 2_000;
pub const CALIBRATION_BINS: usize = 10;
pub const MAX_HORIZON_SECS: u64 = 7 * 86_400;
pub const SCORE_RETENTION_SECS: u64 = 90 * 86_400;
/// Brier score of predicting exactly 0.5, regardless of outcome prevalence.
pub const HALF_PROBABILITY_BRIER: f64 = 0.25;

static NEXT_LEDGER_ID: AtomicU64 = AtomicU64::new(1);

/// An application-owned source registry number, not a permission or identity proof.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SourceId(pub u16);

/// An opaque, non-serializable handle. Only a ledger can issue one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ForecastId {
    ledger: u64,
    sequence: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ForecastError {
    ClockWentBackwards,
    InvalidProbability,
    InvalidDeadline,
    OpenCapacity,
    IdentifierExhausted,
    /// Includes expired, resolved, forgotten, cleared and foreign-ledger IDs.
    UnknownForecast,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RemovedCounts {
    pub open: usize,
    pub scored: usize,
}

/// Descriptive statistics over retained, resolved forecasts for one source.
/// This is neither a confidence interval nor a recommendation to change policy.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SourceSummary {
    pub scored: usize,
    pub mean_probability: f64,
    pub observed_frequency: f64,
    pub mean_brier: f64,
    /// `1 - mean_brier / 0.25`, in [-3, 1]. Compares only with constant 0.5,
    /// not a prevalence-adjusted baseline; it does not measure calibration.
    pub skill_against_half_probability: f64,
}

/// Equal-width bin [lower, upper), except the final bin includes 1.0.
/// Empty bins have no means, rather than an invented zero measurement.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CalibrationBin {
    pub lower: f64,
    pub upper: f64,
    pub count: usize,
    pub mean_probability: Option<f64>,
    pub observed_frequency: Option<f64>,
}

struct OpenForecast {
    id: ForecastId,
    source: SourceId,
    probability: f64,
    resolves_by: u64,
}

struct ScoredForecast {
    source: SourceId,
    probability: f64,
    outcome: bool,
    resolved_at: u64,
}

/// One owner and one logical, nondecreasing clock, in seconds.
///
/// All time-bearing calls advance the clock and remove expired entries before
/// processing the request, even if that request subsequently fails. A backward
/// timestamp changes nothing. Equal timestamps are allowed. Read-only summaries
/// are as of the latest accepted timestamp: call `advance` before viewing them.
///
/// Intentionally not Clone, serializable or Debug: do not duplicate the mutable
/// owner or accidentally format retained measurements into diagnostic logs.
pub struct ForecastLedger {
    ledger_id: u64,
    next_sequence: Option<u64>,
    last_time: Option<u64>,
    open: Vec<OpenForecast>,
    scored: VecDeque<ScoredForecast>,
}

impl ForecastLedger {
    pub fn new() -> Result<Self, ForecastError> {
        Ok(Self {
            ledger_id: allocate_ledger_id(&NEXT_LEDGER_ID)?,
            next_sequence: Some(1),
            last_time: None,
            open: Vec::with_capacity(MAX_OPEN),
            scored: VecDeque::with_capacity(MAX_SCORED),
        })
    }

    pub fn open_count(&self) -> usize {
        self.open.len()
    }

    pub fn scored_count(&self) -> usize {
        self.scored.len()
    }

    /// Admit a finite probability in [0, 1]. The deadline must be strictly
    /// after `now` and at most seven days ahead. Open capacity rejects new work;
    /// it never silently replaces or evicts another live forecast.
    pub fn record(
        &mut self,
        source: SourceId,
        probability: f64,
        now: u64,
        resolves_by: u64,
    ) -> Result<ForecastId, ForecastError> {
        self.advance(now)?;
        if !probability.is_finite() || !(0.0..=1.0).contains(&probability) {
            return Err(ForecastError::InvalidProbability);
        }
        let valid_deadline = resolves_by
            .checked_sub(now)
            .is_some_and(|horizon| (1..=MAX_HORIZON_SECS).contains(&horizon));
        if !valid_deadline {
            return Err(ForecastError::InvalidDeadline);
        }
        if self.open.len() == MAX_OPEN {
            return Err(ForecastError::OpenCapacity);
        }
        let sequence = self
            .next_sequence
            .ok_or(ForecastError::IdentifierExhausted)?;
        let id = ForecastId {
            ledger: self.ledger_id,
            sequence,
        };
        self.next_sequence = sequence.checked_add(1);
        self.open.push(OpenForecast {
            id,
            source,
            probability,
            resolves_by,
        });
        Ok(id)
    }

    /// Score once, only strictly before the deadline. The source and probability
    /// are those admitted by `record`; resolution cannot replace either one.
    /// Late outcomes are dropped unscored, including at the exact deadline.
    pub fn resolve(
        &mut self,
        id: ForecastId,
        outcome: bool,
        now: u64,
    ) -> Result<f64, ForecastError> {
        self.advance(now)?;
        let index = self
            .open
            .iter()
            .position(|forecast| forecast.id == id)
            .ok_or(ForecastError::UnknownForecast)?;
        let forecast = self.open.remove(index);
        let brier = brier_score(forecast.probability, outcome);
        if self.scored.len() == MAX_SCORED {
            self.scored.pop_front();
        }
        self.scored.push_back(ScoredForecast {
            source: forecast.source,
            probability: forecast.probability,
            outcome,
            resolved_at: now,
        });
        Ok(brier)
    }

    /// Expire open entries at their deadline and scores at age 90 days.
    /// Expiry is logical time maintenance, not a background timer or secure erase.
    pub fn advance(&mut self, now: u64) -> Result<RemovedCounts, ForecastError> {
        if self.last_time.is_some_and(|previous| now < previous) {
            return Err(ForecastError::ClockWentBackwards);
        }
        self.last_time = Some(now);
        let open_before = self.open.len();
        let scored_before = self.scored.len();
        self.open.retain(|forecast| now < forecast.resolves_by);
        self.scored
            .retain(|forecast| now.saturating_sub(forecast.resolved_at) < SCORE_RETENTION_SECS);
        Ok(RemovedCounts {
            open: open_before - self.open.len(),
            scored: scored_before - self.scored.len(),
        })
    }

    /// Remove a source's logical records. Does not reuse IDs or reset the clock.
    pub fn forget_source(&mut self, source: SourceId) -> RemovedCounts {
        let open_before = self.open.len();
        let scored_before = self.scored.len();
        self.open.retain(|forecast| forecast.source != source);
        self.scored.retain(|forecast| forecast.source != source);
        RemovedCounts {
            open: open_before - self.open.len(),
            scored: scored_before - self.scored.len(),
        }
    }

    /// Clear logical records, retaining ID and clock watermarks against replay.
    /// Allocation contents, copies and external storage are not securely erased.
    pub fn clear(&mut self) -> RemovedCounts {
        let removed = RemovedCounts {
            open: self.open.len(),
            scored: self.scored.len(),
        };
        self.open.clear();
        self.scored.clear();
        removed
    }

    /// Summarize retained outcomes only. Unresolved and expired predictions are
    /// not evidence of false outcomes. None means no retained observations.
    pub fn summary(&self, source: SourceId) -> Option<SourceSummary> {
        let mut scored = 0usize;
        let mut probabilities = 0.0;
        let mut outcomes = 0usize;
        let mut briers = 0.0;
        for forecast in self.scored.iter().filter(|item| item.source == source) {
            scored += 1;
            probabilities += forecast.probability;
            outcomes += usize::from(forecast.outcome);
            briers += brier_score(forecast.probability, forecast.outcome);
        }
        if scored == 0 {
            return None;
        }
        let mean_brier = briers / scored as f64;
        Some(SourceSummary {
            scored,
            mean_probability: probabilities / scored as f64,
            observed_frequency: outcomes as f64 / scored as f64,
            mean_brier,
            skill_against_half_probability: 1.0 - mean_brier / HALF_PROBABILITY_BRIER,
        })
    }

    /// Empirical calibration, not a skill score or an uncertainty interval.
    /// All ten bins are returned; counts are essential when interpreting means.
    pub fn calibration(&self, source: SourceId) -> [CalibrationBin; CALIBRATION_BINS] {
        let mut bins = std::array::from_fn(|index| CalibrationBin {
            lower: index as f64 / CALIBRATION_BINS as f64,
            upper: (index + 1) as f64 / CALIBRATION_BINS as f64,
            count: 0,
            mean_probability: None,
            observed_frequency: None,
        });
        let mut probabilities = [0.0; CALIBRATION_BINS];
        let mut outcomes = [0usize; CALIBRATION_BINS];
        for forecast in self.scored.iter().filter(|item| item.source == source) {
            let index = bins
                .iter()
                .position(|bin| forecast.probability < bin.upper)
                .unwrap_or(CALIBRATION_BINS - 1);
            bins[index].count += 1;
            probabilities[index] += forecast.probability;
            outcomes[index] += usize::from(forecast.outcome);
        }
        for (index, bin) in bins.iter_mut().enumerate() {
            if bin.count > 0 {
                bin.mean_probability = Some(probabilities[index] / bin.count as f64);
                bin.observed_frequency = Some(outcomes[index] as f64 / bin.count as f64);
            }
        }
        bins
    }
}

fn allocate_ledger_id(counter: &AtomicU64) -> Result<u64, ForecastError> {
    counter
        .try_update(Ordering::Relaxed, Ordering::Relaxed, |next| {
            next.checked_add(1)
        })
        .map_err(|_| ForecastError::IdentifierExhausted)
}

fn brier_score(probability: f64, outcome: bool) -> f64 {
    let target = if outcome { 1.0 } else { 0.0 };
    (probability - target).powi(2)
}

#[cfg(test)]
#[path = "forecast_tests.rs"]
mod tests;
