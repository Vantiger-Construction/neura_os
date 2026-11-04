#!/usr/bin/env bash
# Check workflow syntax, expressions, action inputs and runner labels.
set -euo pipefail

version=1.7.12
sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
scratch=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/neura-actionlint.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
archive="actionlint_${version}_linux_amd64.tar.gz"
curl --fail --location --silent --show-error --retry 3 --max-time 120 \
  "https://github.com/rhysd/actionlint/releases/download/v${version}/${archive}" \
  --output "$scratch/$archive"
printf '%s  %s\n' "$sha256" "$scratch/$archive" | sha256sum --check --strict
tar --no-same-owner -xzf "$scratch/$archive" -C "$scratch" actionlint
# Embedded Bash/Python checks belong to their own test lanes. Keep this
# configuration check independent of optional host-installed analyzers.
"$scratch/actionlint" -shellcheck= -pyflakes=
