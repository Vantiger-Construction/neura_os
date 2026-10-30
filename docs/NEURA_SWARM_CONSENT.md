# Native swarm consent boundary

The Windows Rust swarm is an optional critic and memory-extraction helper. It is
not part of ordinary chat and must never become an unattended cloud path.

The current contract is:

- Startup may load provider-credential storage, but it does not initialize the
  native swarm or copy a provider key into Rust.
- A visible foreground surface must explain that the completed turn will be
  sent to the configured cloud provider for secondary review/extraction.
- Only after that visible confirmation may the surface mint a
  NeuraSwarmApproval.
- The approval expires after five minutes and is consumed once immediately
  before native initialization or one review call.
- Background, Safe Mode, clock rollback, expiry, replay, retry and disposal
  paths fail closed.
- A new turn, retry or provider fallback requires a new approval. Approval for
  primary cloud chat is not approval for swarm review.
- The local Ollama path remains independent: it does not call the swarm,
  cloud router, persistent memory or automatic summarizer.

This is a capability boundary, not a model instruction. The Rust API still
returns safe defaults when no valid approval reaches it, and the Dart wrapper
continues to clear the native credential during Safe Mode and full-data wipe.

The five-minute limit and single-use behavior are covered by
test/services/neura_swarm_policy_test.dart. Physical Windows network,
Safe Mode and process-restart acceptance remain required before treating the
feature as release-ready.
