#!/usr/bin/env bash
# Compose reviewed commits in a disposable checkout, retaining failure evidence.
set -euo pipefail

report="$PWD/avatar-integration-source.txt"
phase='inspect checkout'
printf 'Avatar source composition\nStatus: started\n' > "$report"

finish() {
  local result=$?
  trap - EXIT
  set +e
  {
    printf '\nLast phase: %s\nExit code: %s\n' "$phase" "$result"
    if [ "$result" -eq 0 ]; then
      printf 'Status: complete\nCombined tree: %s\n' "$(git rev-parse 'HEAD^{tree}')"
    else
      printf 'Status: failed; no validated combined tree\nUnmerged paths:\n'
      git diff --name-only --diff-filter=U
    fi
    printf 'Disposable source integration only. No physical audio or lip-sync acceptance.\n'
  } >> "$report"
  cat "$report"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "$report" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit "$result"
}
trap finish EXIT

source_head=$(git rev-parse HEAD)
printf 'Source PR head: %s\nBase: %s\nSAPI pin: %s\nMotion pin: %s\n' \
  "$source_head" "${BASE_HEAD:-unset}" "${SAPI_HEAD:-unset}" "${MOTION_HEAD:-unset}" >> "$report"
for pin in "${BASE_HEAD:-}" "${SAPI_HEAD:-}" "${MOTION_HEAD:-}"; do
  if [[ ! "$pin" =~ ^[0-9a-f]{40}$ ]]; then
    echo '::error::Avatar composition requires full commit SHA pins.'
    exit 1
  fi
done

pinned() {
  local branch=$1 expected=$2 actual
  # The branch being tested uses its checked-out revision; other dependencies
  # must still match the explicitly reviewed pins.
  if [ "${HEAD_REF:-}" = "$branch" ]; then
    printf '%s: current checkout %s\n' "$branch" "$source_head" >> "$report"
    printf '%s\n' "$source_head"
    return
  fi
  if ! actual=$(git ls-remote --exit-code origin "refs/heads/$branch" | cut -f1); then
    printf '%s: unable to read remote head (expected %s)\n' "$branch" "$expected" >> "$report"
    echo "::error::Unable to read avatar dependency $branch." >&2
    return 1
  fi
  printf '%s: expected %s; observed %s\n' "$branch" "$expected" "$actual" >> "$report"
  if [ "$actual" != "$expected" ]; then
    echo "::error::Avatar dependency $branch moved: expected $expected, observed $actual. Review and refresh the pin." >&2
    return 1
  fi
  printf '%s\n' "$expected"
}

phase='verify SAPI head'
SAPI_HEAD=$(pinned neura/sapi-native-visemes "$SAPI_HEAD")
phase='verify motion head'
if [ "${MOTION_IN_BASE:-false}" = true ]; then
  printf 'Motion uses merged commit %s; base ancestry must be verified after fetch.\n' "$MOTION_HEAD" >> "$report"
else
  MOTION_HEAD=$(pinned feature/fluent-motion-neura "$MOTION_HEAD")
fi
phase='fetch pinned history'
git config user.name 'Neura integration validation'
git config user.email 'validation@local.invalid'
# Keep this job's reviewed harness when a dependency carries older CI pins.
# This driver applies only to these workflow files; application, test, lockfile
# and other merge conflicts still fail normally. Nothing is pushed from here.
attributes=$(git rev-parse --git-path info/attributes)
mkdir -p "$(dirname "$attributes")"
printf '\n/.github/workflows/neura-avatar-conversation.yml merge=neura-ci-harness\n' >> "$attributes"
printf '/.github/workflows/neura-windows-tts.yml merge=neura-ci-harness\n' >> "$attributes"
printf '/.github/workflows/neura-visible-mouth.yml merge=neura-ci-harness\n' >> "$attributes"
git config merge.neura-ci-harness.driver true
printf 'Conversation workflow conflict policy keeps source PR head: %s\n' "$source_head" >> "$report"
printf 'Windows speech workflow conflict policy keeps source PR head: %s\n' "$source_head" >> "$report"
printf 'Visible mouth workflow conflict policy keeps source PR head: %s\n' "$source_head" >> "$report"
# Fetch only these commits, avoiding Windows' Neura/neura ref-name collision.
fetch_options=(--no-tags --filter=blob:none)
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  fetch_options+=(--unshallow)
fi
git fetch "${fetch_options[@]}" origin "$BASE_HEAD" "$SAPI_HEAD" "$MOTION_HEAD"
if [ "${MOTION_IN_BASE:-false}" = true ]; then
  phase='verify merged motion ancestry'
  if ! git merge-base --is-ancestor "$MOTION_HEAD" "$BASE_HEAD"; then
    echo '::error::Pinned merged motion commit is not contained in the reviewed base.'
    exit 1
  fi
  printf 'Verified merged motion commit is contained in the reviewed base.\n' >> "$report"
fi
phase='merge base'
git merge --no-edit "$BASE_HEAD"
phase='merge SAPI'
git merge --no-edit "$SAPI_HEAD"
phase='merge motion'
git merge --no-edit "$MOTION_HEAD"
phase='composition complete'
