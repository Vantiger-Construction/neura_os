#!/usr/bin/env bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

if command -v flutter >/dev/null 2>&1; then
  if ! flutter pub get; then
    echo "flutter pub get failed; continuing session startup" >&2
  fi
else
  echo "flutter not found on PATH; skipping pub get" >&2
fi
