# API and system upgrades

This change starts from Neura commit `6917dcf3` and implements three reviewable stages.

## 1. AI, speech, actions and selected context

- OpenAI Responses and Anthropic Messages stream through the same secure router and room-action loop. OpenAI remains primary. A fallback is possible only before any output; it requires its own approval. A tool continuation stays on the selected provider.
- Every cloud request and continuation rechecks Safe Mode and the current constitution, and receives a new preview. The preview includes outgoing text and permitted context. Bodies are frozen before approval. OpenAI requests use `store: false`.
- Function calls are accepted only after a terminal response. Malformed or truncated responses cannot execute tools. The runtime checks the room allowlist again, requires visible approval for each action, limits a turn to four action rounds/eight calls, and rejects duplicate call IDs. Supported actions remain mood-score sharing, local mood logging, room navigation and tone changes.
- The main chat screen now uses the existing opt-in **Speak chat replies** setting for streaming sentence playback. Playback is serialized and queued chunks are discarded on interruption, mute or a mode change. Speech uses the existing device TTS service; this adds no cloud audio or background microphone access.
- The attachment button accepts one UTF-8 TXT, MD, CSV or JSON file, at most 32 KiB, for the next reply. It reads only the selected file and treats its contents as untrusted reference material. It does not index folders or save the attachment. File-derived conversation is not written to long-term memory by this chat screen.
- The next-reply memory checkbox starts off. Recall also requires the room's persistence policy and the constitution to permit it. A constitution that keeps sensitive content local continues to block cloud use of attachments, memory and private action results.
- Once a chat uses a selected file, permitted memory or an approved mood action, later replies retain the private-context flag even after the next-reply controls reset. Derived replies and subsequent turns are excluded from automatic memory storage for the rest of that chat session. Each cloud continuation and follow-up still requires its own preview and approval.

Provider wire formats follow [Responses streaming](https://developers.openai.com/api/docs/guides/streaming-responses), [function calling](https://developers.openai.com/api/docs/guides/function-calling), and [stateless reasoning continuity](https://developers.openai.com/api/docs/guides/reasoning). Models are unchanged. Actual model access and live provider behavior still require account/device QA.

### Streaming performance

- Group arriving chat deltas into one update per scheduled display frame and coalesce scroll callbacks. Flush remaining text before completion or user interruption; discard pending callbacks on disposal or Safe Mode. Reply order, delta counts, fresh approval and generation checks remain intact.
- Scan only newly appended characters for speech boundaries, clearing both scan and playback cursors on completion or interruption. This removes repeated scans and copies of long unfinished sentences.
- Accumulate Anthropic text blocks with `StringBuffer` and materialize their final content only at the terminal event. Tool execution still requires a completed response.

In an isolated Dart 3.12.0 JIT benchmark, a 32,768-character unpunctuated reply delivered as 4,096 growing snapshots took a median 110.293 ms with the previous speech scanner and 0.590 ms after this change (five measured runs after two warmups, identical output). A synthetic burst of 1,000 deltas scheduled one UI update and retained all text. These measure the algorithms, not end-to-end device or provider latency. Thirty focused streaming, speech and batching tests passed in the pure Dart harness; full Flutter/device validation remains required.

### API resilience v1.1 extension

- Provider failures are classified without storing response bodies, prompts or
  credentials. Timeout, connection, rate-limit and provider-availability
  failures are retryable; authentication, quota, invalid-request and malformed
  response failures are not.
- Neura permits at most one same-provider retry before any streamed output.
  The delay honors bounded `Retry-After` guidance or uses jittered backoff, is
  interruptible by barge-in and Safe Mode, and requires a new visible approval
  before the retry leaves the device.
- A tool continuation and any request that already emitted output are never
  retried or switched to another provider. Provider fallback still requires a
  separate preview and approval.
- Passive process-local circuit state opens only after repeated transient
  failures. It sends no background health probes and contains no conversation
  content.
- Request budgeting keeps a contiguous suffix of recent conversation turns,
  preserves the latest user/tool exchange, bounds text, wire and tool-schema
  sizes, and discloses omitted older-message counts in the approval preview.
- Diagnostics now record only counters and timing measurements such as
  time-to-first-token and completion latency. No prompt, response, path, key or
  selected-file content is added to diagnostics.

## 2. Journal sync and recovery

- Fetch remote revisions before uploads, with pagination and a bounded maximum.
- Keep the existing `updated_at` conflict rule and local preference for equal-time divergent content.
- Upload through `neura_sync_journal_revision`, which checks the exact previously read remote revision under a row lock. RLS and the existing server timestamp trigger remain active.
- Re-read local state before merging. A server acknowledgement cannot replace a different local revision created during upload or resurrect a local deletion made during that request.
- Coalesce simultaneous sync requests. Recheck the account and Safe Mode across asynchronous boundaries. Report offline, interrupted, retry-needed and setup-required outcomes explicitly; never claim success for a swallowed error.
- Local journal entries remain the durable source for a manual retry after a failure or restart. No background sync scheduler or separate copy of journal content is introduced.

**Deployment order:** apply `supabase/migrations/20260918181743_compare_journal_revisions.sql` to the intended continuity project before releasing the new client. Missing RPC support produces a setup-required result with no legacy upsert fallback. This PR does not deploy the migration or change account configuration. Existing full-vault encrypted backup and restore remain unchanged; this stage improves recovery from interrupted synchronization.

## 3. Local app API v1

Open **Settings → Local app API** and enable it for the current visible session. It binds only to `127.0.0.1` on a random port. The screen provides the address and a newly generated bearer token. Closing the screen, backgrounding the app, or entering Safe Mode revokes the token and stops the listener. There is no automatic startup or network-wide listener.

All endpoints require `Authorization: Bearer <session-token>` and reject browser Origin headers. No endpoint exposes journal text, files, memories, provider credentials, microphone control, or direct cloud inference.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/v1/health` | Content-free readiness and API version |
| GET | `/v1/capabilities` | Allowed proposal types and approval requirement |
| POST | `/v1/proposals` | Queue a request for native user review; never execute it |
| GET | `/v1/proposals/{id}` | Read a content-free status receipt |

Example body:

```json
{"request_id":"my-app-001","action":"open_room","arguments":{"room":"reflection_bay"}}
```

Other allowed proposals: `set_tone` with a known `tone`, and `sync_journal` with empty arguments. The latter requires a confirmation explaining that journal entries go to the configured cloud account. Request IDs are idempotent within a session; reusing one for different arguments is rejected. Proposals expire after two minutes. Limits: 4 KiB bodies, 60 authenticated requests/minute, eight simultaneous handlers, 16 active proposals, 64 retained receipts and 256 non-replayable request IDs per session. There is no HTTP approval endpoint.

This first API serves trusted applications on the same device. Windows–Android continuity uses the configured sync backend; cross-device LAN control is not enabled.

### Local API v1.1 resilience extension

- The checked-in contract is `docs/neura-local-api-v1.openapi.json`. Clients
  send `X-Neura-Api-Version: 1`; responses include the negotiated major version
  and a content-free `X-Neura-Trace-Id`.
- `/v1/capabilities` now advertises action argument contracts and operational
  limits. The Dart and PowerShell clients consume those contracts rather than
  carrying separate room and tone allowlists.
- Existing string error codes remain compatible with v1 clients. A typed
  `error_info` object adds retryability and trace correlation, while temporary
  pressure responses include `Retry-After`.
- Final receipts are pruned independently of session request-ID tombstones.
  This prevents completed receipts from exhausting the active queue without
  permitting a retired request ID to replay an action.

## Validation and release checks

Re-run the isolated database test with `npm ci --prefix tools/sync_tests` followed by `npm test --prefix tools/sync_tests`. It creates an in-memory database and uses synthetic identities only.

- Focused protocol, context, speech-queue, local-API and recovery tests run without provider credentials or cloud requests.
- Router tests cover fresh fallback approval, partial-stream failure, cancellation while approval is open, Safe Mode during approval, private history, and restoration of the local-only rule during approval.
- Sync session tests cover remote-before-local ordering, edits during upload, account changes and offline behavior.
- The migration was exercised in an isolated PostgreSQL-compatible PGlite instance: insert/update, stale-revision rejection, idempotent payloads, ownership isolation and anonymous access denial passed.
- Local Flutter startup was blocked by automatic approval review because it attempted instance-metadata access. Full Flutter analysis/tests and Windows/Android packaging must pass the existing CI before merge. No CI gate is removed or relaxed.
- Device QA remains: provider streaming and fallback, TTS barge-in, attachment preview, local-client approval flow, and two-device sync after migration deployment.

No merge, migration deployment, paid service activation or provider request is performed by creating this PR.

## Deployment update — September 18, 2026

The existing Supabase project was restored and the journal migrations were deployed and verified. See [deployment evidence](SUPABASE_DEPLOYMENT_20260918.md). Full Flutter CI and platform builds passed for PR #87; configured physical-device QA remains pending. Historical preparation notes above describe the PR before deployment.
