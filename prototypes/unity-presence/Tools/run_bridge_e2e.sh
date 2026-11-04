#!/usr/bin/env bash
# End-to-end live-bridge check: real neura_api with the presence relay on,
# a raw publisher socket, and the Unity bridge's PresenceRelayClient.
# Needs cargo, mcs and mono. Run from anywhere.
set -euo pipefail
prototype_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd -- "$prototype_root/../.." && pwd)"
temporary_dir="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

cargo build --quiet --locked --manifest-path "$repo_root/rust/Cargo.toml" --bin neura_api
"${MCS_BIN:-mcs}" -nologo -warnaserror -out:"$temporary_dir/BridgeEndToEnd.exe" \
  "$prototype_root"/Assets/Presence/Core/*.cs \
  "$prototype_root"/Assets/Presence/Bridge/Protocol/*.cs \
  "$prototype_root/Tools/BridgeEndToEnd.cs"

token="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
mkfifo "$temporary_dir/ready"
NEURA_API_ADDR=127.0.0.1:0 NEURA_API_SESSION_TOKEN="$token" NEURA_API_PRESENCE_RELAY=1 \
  NEURA_API_LAUNCHER_READY=1 "$repo_root/rust/target/debug/neura_api" >"$temporary_dir/ready" 2>/dev/null &
server_pid=$!
read -r -t 20 marker address <"$temporary_dir/ready"
test "$marker" = "NEURA_IPC_READY"

NEURA_PRESENCE_RELAY_ADDR="$address" NEURA_PRESENCE_TOKEN="$token" \
  "${MONO_BIN:-mono}" "$temporary_dir/BridgeEndToEnd.exe"
