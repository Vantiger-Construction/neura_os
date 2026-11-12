use super::*;

const A: SourceId = SourceId(1);
const B: SourceId = SourceId(2);

fn ledger() -> ForecastLedger {
    ForecastLedger::new().unwrap()
}

fn close(actual: f64, expected: f64) {
    assert!(actual.is_finite());
    assert!((actual - expected).abs() < 1e-12, "{actual} != {expected}");
}

fn score(ledger: &mut ForecastLedger, source: SourceId, p: f64, outcome: bool, now: u64) {
    let id = ledger.record(source, p, now, now + 10).unwrap();
    ledger.resolve(id, outcome, now).unwrap();
}

#[test]
fn empty_source_has_no_invented_measurements() {
    let ledger = ledger();
    assert_eq!(ledger.open_count(), 0);
    assert_eq!(ledger.scored_count(), 0);
    assert_eq!(ledger.summary(A), None);
    for (index, bin) in ledger.calibration(A).iter().enumerate() {
        close(bin.lower, index as f64 / 10.0);
        close(bin.upper, (index + 1) as f64 / 10.0);
        assert_eq!(bin.count, 0);
        assert_eq!(bin.mean_probability, None);
        assert_eq!(bin.observed_frequency, None);
    }
}

#[test]
fn probabilities_are_rejected_instead_of_silently_clamped() {
    let mut ledger = ledger();
    for p in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, -0.01, 1.01] {
        assert_eq!(
            ledger.record(A, p, 0, 1),
            Err(ForecastError::InvalidProbability)
        );
    }
    assert_eq!(ledger.next_sequence, Some(1));
    assert_eq!(ledger.open_count(), 0);
    assert_eq!(ledger.scored_count(), 0);
    assert!(ledger.record(A, 0.0, 0, 1).is_ok());
    assert!(ledger.record(A, 1.0, 0, 1).is_ok());
}

#[test]
fn deadline_must_be_future_and_within_bounded_horizon() {
    let mut ledger = ledger();
    for deadline in [9, 10, 11 + MAX_HORIZON_SECS] {
        assert_eq!(
            ledger.record(A, 0.5, 10, deadline),
            Err(ForecastError::InvalidDeadline)
        );
    }
    assert!(ledger.record(A, 0.5, 10, 11).is_ok());
    assert!(ledger.record(A, 0.5, 10, 10 + MAX_HORIZON_SECS).is_ok());
}

#[test]
fn timestamp_extremes_do_not_wrap() {
    let mut ledger = ledger();
    let id = ledger.record(A, 0.5, u64::MAX - 1, u64::MAX).unwrap();
    close(ledger.resolve(id, true, u64::MAX - 1).unwrap(), 0.25);
    assert_eq!(
        ledger.record(A, 0.5, u64::MAX, 0),
        Err(ForecastError::InvalidDeadline)
    );
    assert_eq!(
        ledger.record(A, 0.5, u64::MAX, u64::MAX),
        Err(ForecastError::InvalidDeadline)
    );
    assert_eq!(ledger.advance(u64::MAX).unwrap(), RemovedCounts::default());
}

#[test]
fn brier_scores_match_binary_probability_arithmetic() {
    let mut ledger = ledger();
    let first = ledger.record(A, 0.8, 0, 10).unwrap();
    let second = ledger.record(A, 0.2, 0, 10).unwrap();
    close(ledger.resolve(first, true, 1).unwrap(), 0.04);
    close(ledger.resolve(second, true, 1).unwrap(), 0.64);
    let summary = ledger.summary(A).unwrap();
    assert_eq!(summary.scored, 2);
    close(summary.mean_probability, 0.5);
    close(summary.observed_frequency, 1.0);
    close(summary.mean_brier, 0.34);
    close(summary.skill_against_half_probability, -0.36);
}

#[test]
fn duplicate_resolution_cannot_score_again_or_change_source() {
    let mut ledger = ledger();
    let id = ledger.record(A, 0.9, 0, 10).unwrap();
    ledger.resolve(id, true, 1).unwrap();
    assert_eq!(
        ledger.resolve(id, false, 1),
        Err(ForecastError::UnknownForecast)
    );
    assert_eq!(ledger.scored_count(), 1);
    assert_eq!(ledger.summary(A).unwrap().scored, 1);
    assert_eq!(ledger.summary(B), None);
    // There is no record/resolve parameter that can replace this ID's source.
    let other = ledger.record(B, 0.1, 1, 10).unwrap();
    assert_ne!(other, id);
    ledger.resolve(other, false, 1).unwrap();
    assert_eq!(ledger.summary(A).unwrap().scored, 1);
    assert_eq!(ledger.summary(B).unwrap().scored, 1);
}

#[test]
fn foreign_ledger_id_cannot_resolve_a_matching_sequence() {
    let mut first = ledger();
    let mut second = ledger();
    let first_id = first.record(A, 0.9, 0, 10).unwrap();
    let second_id = second.record(A, 0.9, 0, 10).unwrap();
    assert_eq!(first_id.sequence, second_id.sequence);
    assert_ne!(first_id, second_id);
    assert_eq!(
        second.resolve(first_id, true, 1),
        Err(ForecastError::UnknownForecast)
    );
    assert_eq!(second.open_count(), 1);
    assert_eq!(second.scored_count(), 0);
    second.resolve(second_id, true, 1).unwrap();
    first.resolve(first_id, true, 1).unwrap();
}

#[test]
fn exact_deadline_and_late_resolution_expire_without_prior_sweep() {
    let mut ledger = ledger();
    let before = ledger.record(A, 0.5, 0, 10).unwrap();
    let at = ledger.record(A, 0.5, 0, 10).unwrap();
    let after = ledger.record(A, 0.5, 0, 12).unwrap();
    ledger.resolve(before, true, 9).unwrap();
    assert_eq!(
        ledger.resolve(at, true, 10),
        Err(ForecastError::UnknownForecast)
    );
    assert_eq!(
        ledger.resolve(after, false, 13),
        Err(ForecastError::UnknownForecast)
    );
    assert_eq!(ledger.open_count(), 0);
    assert_eq!(ledger.scored_count(), 1);
    close(ledger.summary(A).unwrap().observed_frequency, 1.0);
}

#[test]
fn backward_timestamps_change_neither_records_nor_watermarks() {
    let mut ledger = ledger();
    let id = ledger.record(A, 0.8, 10, 20).unwrap();
    let next = ledger.next_sequence;
    assert_eq!(ledger.advance(9), Err(ForecastError::ClockWentBackwards));
    assert_eq!(
        ledger.resolve(id, true, 9),
        Err(ForecastError::ClockWentBackwards)
    );
    assert_eq!(
        ledger.record(B, 0.2, 9, 30),
        Err(ForecastError::ClockWentBackwards)
    );
    assert_eq!(ledger.last_time, Some(10));
    assert_eq!(ledger.next_sequence, next);
    assert_eq!(ledger.open_count(), 1);
    assert_eq!(ledger.scored_count(), 0);
    ledger.resolve(id, true, 10).unwrap();
}

#[test]
fn failed_requests_still_observe_time_and_expire_records() {
    let mut ledger = ledger();
    let id = ledger.record(A, 0.5, 0, 10).unwrap();
    assert_eq!(
        ledger.record(B, f64::NAN, 10, 20),
        Err(ForecastError::InvalidProbability)
    );
    assert_eq!(ledger.open_count(), 0);
    assert_eq!(ledger.last_time, Some(10));
    assert_eq!(
        ledger.resolve(id, true, 9),
        Err(ForecastError::ClockWentBackwards)
    );
    assert_eq!(
        ledger.resolve(id, true, 15),
        Err(ForecastError::UnknownForecast)
    );
    assert_eq!(ledger.last_time, Some(15));
    assert_eq!(ledger.scored_count(), 0);
}

#[test]
fn full_open_capacity_rejects_without_evicting_live_work_or_consuming_id() {
    let mut ledger = ledger();
    let first = ledger.record(A, 0.5, 0, 100).unwrap();
    for _ in 1..MAX_OPEN {
        ledger.record(A, 0.5, 0, 100).unwrap();
    }
    let next = ledger.next_sequence;
    assert_eq!(
        ledger.record(B, 0.5, 1, 100),
        Err(ForecastError::OpenCapacity)
    );
    assert_eq!(ledger.next_sequence, next);
    assert_eq!(ledger.open_count(), MAX_OPEN);
    ledger.resolve(first, true, 1).unwrap();
    assert!(ledger.record(B, 0.5, 1, 100).is_ok());
    assert_eq!(ledger.open_count(), MAX_OPEN);
}

#[test]
fn admission_clears_expired_open_capacity_without_scoring_it() {
    let mut ledger = ledger();
    let old = ledger.record(A, 0.5, 0, 1).unwrap();
    for _ in 1..MAX_OPEN {
        ledger.record(A, 0.5, 0, 1).unwrap();
    }
    ledger.record(B, 0.2, 1, 2).unwrap();
    assert_eq!(ledger.open_count(), 1);
    assert_eq!(ledger.scored_count(), 0);
    assert_eq!(
        ledger.resolve(old, true, 1),
        Err(ForecastError::UnknownForecast)
    );
}

#[test]
fn oldest_score_eviction_does_not_permit_replay() {
    let mut ledger = ledger();
    let old = ledger.record(A, 1.0, 0, 10).unwrap();
    ledger.resolve(old, false, 0).unwrap();
    for _ in 0..MAX_SCORED {
        score(&mut ledger, B, 1.0, true, 0);
    }
    assert_eq!(ledger.scored_count(), MAX_SCORED);
    assert_eq!(ledger.summary(A), None);
    close(ledger.summary(B).unwrap().mean_brier, 0.0);
    assert_eq!(
        ledger.resolve(old, true, 0),
        Err(ForecastError::UnknownForecast)
    );
    assert_eq!(ledger.scored_count(), MAX_SCORED);
}

#[test]
fn score_age_expiry_is_exact_and_does_not_become_a_false_outcome() {
    let mut ledger = ledger();
    score(&mut ledger, A, 0.8, true, 10);
    score(&mut ledger, B, 0.2, false, 11);
    assert_eq!(
        ledger.advance(10 + SCORE_RETENTION_SECS - 1).unwrap(),
        RemovedCounts::default()
    );
    assert_eq!(ledger.scored_count(), 2);
    assert_eq!(
        ledger.advance(10 + SCORE_RETENTION_SECS).unwrap(),
        RemovedCounts { open: 0, scored: 1 }
    );
    assert_eq!(ledger.summary(A), None);
    close(ledger.summary(B).unwrap().observed_frequency, 0.0);
    assert_eq!(
        ledger.advance(11 + SCORE_RETENTION_SECS).unwrap(),
        RemovedCounts { open: 0, scored: 1 }
    );
    assert_eq!(ledger.scored_count(), 0);
}

#[test]
fn forgetting_one_source_preserves_others_and_never_reuses_ids() {
    let mut ledger = ledger();
    score(&mut ledger, A, 0.8, true, 0);
    score(&mut ledger, B, 0.2, false, 0);
    let old = ledger.record(A, 0.5, 0, 10).unwrap();
    let retained = ledger.record(B, 0.5, 0, 10).unwrap();
    assert_eq!(
        ledger.forget_source(A),
        RemovedCounts { open: 1, scored: 1 }
    );
    assert_eq!(ledger.forget_source(A), RemovedCounts::default());
    assert_eq!(ledger.summary(A), None);
    assert_eq!(ledger.summary(B).unwrap().scored, 1);
    let fresh = ledger.record(A, 0.7, 0, 10).unwrap();
    assert_ne!(fresh, old);
    assert!(fresh.sequence > retained.sequence);
    assert_eq!(
        ledger.resolve(old, true, 0),
        Err(ForecastError::UnknownForecast)
    );
    ledger.resolve(retained, true, 0).unwrap();
    ledger.resolve(fresh, true, 0).unwrap();
}

#[test]
fn clear_revokes_handles_but_preserves_clock_and_sequence() {
    let mut ledger = ledger();
    score(&mut ledger, A, 0.8, true, 10);
    let old = ledger.record(A, 0.5, 10, 20).unwrap();
    assert_eq!(ledger.clear(), RemovedCounts { open: 1, scored: 1 });
    assert_eq!(ledger.clear(), RemovedCounts::default());
    assert_eq!(ledger.advance(9), Err(ForecastError::ClockWentBackwards));
    let fresh = ledger.record(B, 0.5, 10, 20).unwrap();
    assert_ne!(fresh, old);
    assert_eq!(fresh.sequence, old.sequence + 1);
    assert_eq!(
        ledger.resolve(old, true, 10),
        Err(ForecastError::UnknownForecast)
    );
    ledger.resolve(fresh, true, 10).unwrap();
}

#[test]
fn sequence_exhaustion_never_wraps_even_after_clear() {
    let mut ledger = ledger();
    ledger.next_sequence = Some(u64::MAX);
    let last = ledger.record(A, 0.5, 0, 10).unwrap();
    assert_eq!(last.sequence, u64::MAX);
    assert_eq!(ledger.next_sequence, None);
    assert_eq!(
        ledger.record(A, 0.5, 0, 10),
        Err(ForecastError::IdentifierExhausted)
    );
    ledger.clear();
    assert_eq!(
        ledger.record(A, 0.5, 0, 10),
        Err(ForecastError::IdentifierExhausted)
    );
    assert_eq!(ledger.open_count(), 0);
}

#[test]
fn ledger_identity_exhaustion_is_fail_closed() {
    // Local counter avoids mutating the process allocator in parallel tests.
    let counter = AtomicU64::new(u64::MAX - 1);
    assert_eq!(allocate_ledger_id(&counter).unwrap(), u64::MAX - 1);
    assert_eq!(
        allocate_ledger_id(&counter),
        Err(ForecastError::IdentifierExhausted)
    );
    assert_eq!(counter.load(Ordering::Relaxed), u64::MAX);
}

#[test]
fn calibration_uses_exact_half_open_boundaries_and_includes_one() {
    let mut ledger = ledger();
    for index in 0..=CALIBRATION_BINS {
        score(
            &mut ledger,
            A,
            index as f64 / 10.0,
            index.is_multiple_of(2),
            0,
        );
    }
    let bins = ledger.calibration(A);
    for bin in &bins[..CALIBRATION_BINS - 1] {
        assert_eq!(bin.count, 1);
        close(bin.mean_probability.unwrap(), bin.lower);
    }
    assert_eq!(bins[9].count, 2);
    close(bins[9].mean_probability.unwrap(), 0.95);
    close(bins[9].observed_frequency.unwrap(), 0.5);
    assert_eq!(bins.iter().map(|bin| bin.count).sum::<usize>(), 11);
}

#[test]
fn probabilities_immediately_below_boundaries_stay_in_previous_bin() {
    let mut ledger = ledger();
    for index in 1..CALIBRATION_BINS {
        let boundary = index as f64 / CALIBRATION_BINS as f64;
        let below = f64::from_bits(boundary.to_bits() - 1);
        score(&mut ledger, A, below, false, 0);
    }
    let bins = ledger.calibration(A);
    for bin in &bins[..CALIBRATION_BINS - 1] {
        assert_eq!(bin.count, 1);
        assert!(bin.mean_probability.unwrap() < bin.upper);
    }
    assert_eq!(bins[9].count, 0);
}

#[test]
fn empirical_calibration_and_half_probability_skill_are_distinct() {
    let mut ledger = ledger();
    // Exactly calibrated at 0.5, but has no skill relative to constant 0.5.
    for index in 0usize..20 {
        score(&mut ledger, A, 0.5, index.is_multiple_of(2), 0);
    }
    let bin = ledger.calibration(A)[5];
    close(bin.mean_probability.unwrap(), 0.5);
    close(bin.observed_frequency.unwrap(), 0.5);
    close(
        ledger.summary(A).unwrap().skill_against_half_probability,
        0.0,
    );

    // Beats constant 0.5 here, yet predicted 0.1 differs from observed 0.0.
    for _ in 0..20 {
        score(&mut ledger, B, 0.1, false, 0);
    }
    let bin = ledger.calibration(B)[1];
    close(bin.mean_probability.unwrap(), 0.1);
    close(bin.observed_frequency.unwrap(), 0.0);
    close(
        ledger.summary(B).unwrap().skill_against_half_probability,
        0.96,
    );
}

#[test]
fn summary_bounds_hold_at_perfect_and_worst_predictions() {
    let mut ledger = ledger();
    score(&mut ledger, A, 0.0, false, 0);
    score(&mut ledger, A, 1.0, true, 0);
    score(&mut ledger, B, 0.0, true, 0);
    score(&mut ledger, B, 1.0, false, 0);
    close(ledger.summary(A).unwrap().mean_brier, 0.0);
    close(
        ledger.summary(A).unwrap().skill_against_half_probability,
        1.0,
    );
    close(ledger.summary(B).unwrap().mean_brier, 1.0);
    close(
        ledger.summary(B).unwrap().skill_against_half_probability,
        -3.0,
    );
}

#[test]
fn mixed_synthetic_history_preserves_bounds_and_source_isolation() {
    let mut ledger = ledger();
    for step in 0..(MAX_SCORED * 2) {
        let now = step as u64;
        let source = SourceId((step % 4) as u16);
        let p = (step % 101) as f64 / 100.0;
        let id = ledger.record(source, p, now, now + 2).unwrap();
        if !step.is_multiple_of(3) {
            let brier = ledger.resolve(id, step.is_multiple_of(2), now).unwrap();
            assert!((0.0..=1.0).contains(&brier));
            assert_eq!(
                ledger.resolve(id, false, now),
                Err(ForecastError::UnknownForecast)
            );
        }
        if step.is_multiple_of(113) {
            ledger.forget_source(SourceId(((step + 1) % 4) as u16));
        }
        if step.is_multiple_of(997) {
            ledger.clear();
        }
        assert!(ledger.open_count() <= MAX_OPEN);
        assert!(ledger.scored_count() <= MAX_SCORED);
        assert!(ledger.open.iter().all(|entry| entry.resolves_by > now));
    }
    let mut total = 0;
    for source in [SourceId(0), A, B, SourceId(3)] {
        let bins = ledger.calibration(source);
        let binned = bins.iter().map(|bin| bin.count).sum::<usize>();
        let summary = ledger.summary(source);
        assert_eq!(summary.map_or(0, |value| value.scored), binned);
        if let Some(summary) = summary {
            assert!(summary.mean_brier.is_finite());
            assert!((0.0..=1.0).contains(&summary.mean_brier));
            assert!((-3.0..=1.0).contains(&summary.skill_against_half_probability));
            total += summary.scored;
        }
        for bin in bins.iter().filter(|bin| bin.count > 0) {
            assert!((0.0..=1.0).contains(&bin.mean_probability.unwrap()));
            assert!((0.0..=1.0).contains(&bin.observed_frequency.unwrap()));
        }
    }
    assert_eq!(total, ledger.scored_count());
}
