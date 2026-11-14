# Suggestion calibration integration review

This is the separate integration review that
[FORECAST_CALIBRATION_FOUNDATION.md](FORECAST_CALIBRATION_FOUNDATION.md) requires
before forecast calibration touches runtime behaviour. It covers one use only:
measuring how well the Autonomy Kernel's score for a proactive suggestion card
matched whether the user accepted that card. The effect is display-only.

## Where it runs

The Rust ledger in `rust/src/attunement/forecast.rs` is loaded only by the
Windows native swarm, after a fresh foreground cloud approval, and never in
Safe Mode. Proactive suggestions are local Dart on every platform. Routing
local calibration through that loader would make a local feature depend on
cloud consent, so the ledger contract is ported to Dart instead:

- `lib/intelligence/forecast_calibration.dart` keeps the same caps, horizon,
  retention, expiry, clock, identifier and error rules as the Rust ledger. Its
  tests mirror `forecast_tests.rs` one-for-one, apart from the u64 timestamp
  extremes, which do not apply to Dart's integers. Identifiers stop at
  2^53 - 1 so they're exact on every Dart target.
- The Rust module is unchanged and remains inactive. If either copy's contract
  changes, change both and their mirrored tests together.

## Event definition

- **Forecast:** recorded once, when a suggestion card first reaches a rendered
  frame (`NeuraIntelligenceController.markShown`, called by the banner after a
  rendered-frame acknowledgement). Cards that are evaluated but never rendered
  are not forecast.
- **Probability:** the kernel's decision-receipt `score` for that card. That
  score was not designed as a probability. How far it is from one is exactly
  what this measures.
- **Deadline:** the candidate's own `expiresAt`, at most seven days ahead
  (otherwise it's not recorded).
- **Outcome:** `true` when the user accepts the card strictly before the
  deadline; `false` when they dismiss it before the deadline. Accepting means
  tapping the primary action. For a card that needs approval (an
  approval-gated quest), it means approving in the review screen, and
  declining there counts as not accepted. Either way, the outcome is whatever
  the card records through `recordOutcome`, the same signal specialist
  reputation already uses.
- **Time resolution:** whole seconds, per the ledger contract, taken when the
  gesture happens, not when its queued write runs. Truncating both the gesture
  and the deadline can only drop a gesture made in the card's final partial
  second as late. It can never score a late gesture as on time.
- **No outcome:** a card that expires without a gesture, or whose gesture
  arrives at or after expiry, is dropped unscored. It is never counted as a
  rejection.

## Trustworthy outcome evidence

Outcomes come only from the dashboard banner's own gesture handlers through
`ProactiveBannerService.recordOutcome`. Model output, retrieved documents,
other specialists and timestamps supplied by anything other than the app's own
clock cannot resolve a forecast. A forecast resolves at most once; repeated
gestures or a second "shown" don't add measurements. A clock rollback changes
nothing. A card shown during a rollback isn't measured. A gesture made during a
rollback leaves the card open for a later gesture or for expiry.

## Sources

Sources are a fixed registry in `NeuraCalibrationSources`
(`lib/intelligence/suggestion_calibration.dart`) of stable numeric ids for the
initiative, opportunity-radar, joy and relationship specialists. Unregistered
specialists are never forecast.

Care support (`opportunity_radar.care_support`) is excluded on purpose.
Whether someone accepts a care card doesn't show whether offering it was right.
Care must never look like an engagement target, even on a display-only screen.

## Consent and gates

Measurement runs only while all of these hold, which are the same gates as
routine initiative:

- proactive suggestions are on (level is not Off),
- local learning (`HumanPrefs.allowLearning`) is on,
- Safe Mode is off,
- the controller is not suspended for a data wipe.

The controller listens to the learning and Safe Mode settings and clears every
measurement, open forecast and pending offer the moment either gate closes.
Turning proactive suggestions off clears it in `updatePreferences`. Every
calibration call also re-checks the gates. Re-enabling starts empty; nothing
resumes.

## Effect: display-only

The Intelligence Center's **How suggestions land** card lists, per source,
the mean score, the share of answered cards that were accepted, and the
answered-card count. It makes no accuracy or confidence claim and shows counts
with every figure.

Nothing reads these statistics except that card. They don't feed the kernel,
specialist reputation, daily caps, cooldowns, routing or any other decision.
Changing that needs its own review.

## Retention and deletion

- In memory only, for the life of the app process. Nothing is written to
  preferences, encrypted memory, the Timeline Vault or logs, and the ledger
  has no serialization path. Persisting it later needs the OS-backed
  encryption, ownership, drain and verified-deletion work listed in the
  foundation doc.
- Within a process, the ledger's own bounds apply: 256 open forecasts, 2,000
  scores, and scores expire at 90 days. Receipt bookkeeping holds at most 100
  offers and 256 open handles.
- **Clear** in Decision receipts, the gate closing, and data wipe
  (`resetAfterDataWipe`) all clear the ledger. As in the Rust contract,
  clearing removes logical records and keeps the identifier and clock
  watermarks so cleared handles can't be replayed. It isn't a secure erase of
  process memory.

## UI wording

> Compares Neura's score for each card you saw with whether you accepted it
> before it expired. Kept on this device for this session only, and it doesn't
> change what Neura suggests. Care cards are never measured.

While the gates are closed, the card reads **Not measuring** and names the
three settings. It doesn't show the last values.

## Validation

Synthetic tests only:

- `test/intelligence/forecast_calibration_test.dart`: ledger parity with the
  Rust contract.
- `test/intelligence/suggestion_calibration_test.dart`: event definition,
  expiry and late gestures, registry and care exclusion, duplicate shows,
  gate clearing, clock rollback, controller wiring, history clear, data wipe,
  and the absence of calibration data in persisted decision history.

Run the Flutter lanes in `AGENTS.md` on the final revision. This change adds no
native, model, cloud or platform behaviour.
