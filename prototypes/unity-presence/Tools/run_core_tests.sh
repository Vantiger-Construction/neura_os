#!/usr/bin/env bash
set -euo pipefail
prototype_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT
compiler_path="${MCS_BIN:-mcs}"
runtime_path="${MONO_BIN:-mono}"
"$compiler_path" -nologo -warnaserror -out:"$temporary_dir/ContractTests.exe" \
  "$prototype_root"/Assets/Presence/Core/*.cs \
  "$prototype_root/Assets/Presence/Tests/Shared/ContractCases.cs" \
  "$prototype_root/Tools/ContractTestRunner.cs"
"$runtime_path" "$temporary_dir/ContractTests.exe"
