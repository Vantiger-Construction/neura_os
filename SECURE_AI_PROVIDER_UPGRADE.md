# Secure AI Provider upgrade

## Included

- OS-backed encrypted storage for the Anthropic credential.
- One-time migration from an older `--dart-define=ANTHROPIC_API_KEY` build.
- Settings > AI Provider screen to add, replace, or remove the key.
- Existing streaming, barge-in, room tools, memory, diagnostics, and local
  fallback behavior remain in place.
- Focused credential-format tests.

## Required release action

After installing this upgrade and opening Neura once, rebuild future releases
without `--dart-define=ANTHROPIC_API_KEY=...`. A build-time secret remains
recoverable from the compiled application even when the source repository is
private.

If a real key was previously included in a shared ZIP or installer, revoke it
in the provider console and save a replacement through Settings > AI Provider.
