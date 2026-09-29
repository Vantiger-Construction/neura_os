# Provider-bound cloud transaction envelope

Every outbound model attempt now has a process-local transaction envelope
created before the approval dialog opens.

## Envelope fields

- fresh approval ID for this exact attempt;
- trace ID shared only by the logical user request;
- idempotency key shared only by an exact retry to the same provider;
- SHA-256 fingerprint of the frozen logical payload;
- provider and exact HTTPS audience;
- retry count and `inputRequired` approval state; and
- mandatory private/no-store cache policy.

A provider fallback receives a new audience and idempotency key. An exact
retry keeps the key but receives a new approval ID and another visible
approval. A tool continuation still never retries or switches providers.

## Transport boundary

The OpenAI and Anthropic transports reject missing or mismatched envelopes.
Operational headers contain the approval, trace, and idempotency identifiers
plus `Cache-Control: no-store` and `Pragma: no-cache`. Prompt text and the
prompt fingerprint are never sent as Neura headers.

Credentials remain read from the provider-specific secure-storage slot only
after the provider has been selected. The envelope then binds that attempt to
the provider's exact audience.

## Audit boundary

The bounded in-process audit trail records stage, provider, audience host,
retry count, approval ID, trace ID, UTC time, and a stable failure kind. Its
event type has no prompt, response, credential, local path, or digest field.
It is not persisted by this slice.

## Preserved controls

- Safe Mode and the Personal Constitution are checked before approval and
  again before every send.
- Every retry and fallback requires a new visible decision.
- Denial, cancellation, or policy tightening prevents the transport call.
- Shared provider caching is prohibited; OpenAI requests continue to set
  `store: false`.
- Redirects remain disabled for streamed requests.

