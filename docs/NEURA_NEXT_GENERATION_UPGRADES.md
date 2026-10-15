# Neura next-generation upgrade track

Status: first implementation slice; review required. No automatic merge.
Baseline: a4e8c5e793d4aa3764c66a47819c395b555c786b.

## Implemented in this proposal

- Offline Ollama requests explicitly set top-level `think: false`, requesting direct answers where the pinned model supports this control. This does not guarantee a latency improvement on an already non-thinking instruct model.
- Reject an advertised response larger than the existing byte budget before waiting for its body. Chunk-by-chunk limits still reject oversized bodies without a Content-Length.
- Bound the existing per-request HTTP pool to one idle connection and a 15-second idle timeout. The client remains scoped to the cancellable inference worker; no process-global client outlives its Tokio runtime.
- Add a synthetic loopback regression whose oversized response body never arrives, and assert direct-answer mode in payload and mock-server tests.

Source: https://github.com/ollama/ollama/blob/main/docs/capabilities/thinking.mdx
Connection pooling: https://docs.rs/reqwest/0.12/reqwest/struct.ClientBuilder.html

No model residency change: keep_alive remains zero. No automatic model download, cloud fallback, tool execution, retained transcript, new telemetry or background inference. Existing model identity, loopback endpoint, proxy/redirect rejection, cancellation, memory admission and Safe Mode controls remain in place.

## Next implementation milestones

These are designs, not shipped capabilities.

| Upgrade | Implementation boundary | Acceptance evidence |
| --- | --- | --- |
| Measured response budgets | Session-only monotonic phase timings for model preflight, inference and presentation; fixed labels, no prompts or replies | Synthetic timer tests and opt-in physical-device p50/p95 measurements; no performance claim without a baseline |
| Adaptive local intelligence | Explicitly selected profiles validated against local model metadata and available RAM; never silently select a remote model | Low-memory, wrong-model, cancellation and no-network regressions plus device comparison |
| Explainable encrypted recall | User-approved retrieval using existing encrypted-memory leases; bounded selected-record decrypts; source receipts | Lease expiry/revocation, wipe-generation, corrupt-tail and no-plaintext persistence checks |
| Responsive companion presence | Extend existing startup breathing animation to activity states; shared image cache, frame isolation, reduced-motion and lifecycle suspension | Widget lifecycle tests and Windows/Android frame-time and memory recordings |
| Recoverable action plans | Preview proposed steps, apply scoped approval, append outcome receipts, offer rollback where possible | Revocation between steps, stale approval, partial failure and restart tests; no autonomous external action |
| Explicit device continuity | User-initiated encrypted handoff with revision-aware conflict preview; local journal authoritative | Offline queue, duplicate delivery, interrupted handoff and conflicting journal revision tests |

## Validation

Required: existing Neura Ollama Chat workflow runs Rust tests, strict Clippy, formatting, Flutter adapter/lifecycle tests and Windows preview checks. The Rust source path already triggers it.

No Rust or Flutter toolchain is installed in the authoring workspace. Compilation, formatter conformance and test execution are pending; source review is not a passing test result. The repository's recent hosted-runner billing blocker may prevent CI from starting. Do not bypass checks.

Physical-device acceptance must compare the same model, prompt set, cold-start state and hardware. Record failed/empty replies as well as latency, RAM and answer usefulness. Direct-answer mode may trade reasoning depth for responsiveness and must be evaluated before release.
