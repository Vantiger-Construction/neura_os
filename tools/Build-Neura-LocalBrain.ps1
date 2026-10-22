#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Run)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifest = Join-Path $root 'rust\Cargo.toml'

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw 'Rust/cargo is required. Install it from https://rustup.rs and rerun.'
}

Push-Location $root
try {
    & cargo fmt --manifest-path $manifest
    if ($LASTEXITCODE -ne 0) { throw 'cargo fmt failed.' }
    & cargo test --manifest-path $manifest
    if ($LASTEXITCODE -ne 0) { throw 'cargo test failed.' }
    & cargo build --release --bin neura_api --manifest-path $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Local brain build failed.' }

    $exe = Join-Path $root 'rust\target\release\neura_api.exe'
    Write-Host "[OK] Local brain built: $exe" -ForegroundColor Green
    if ($Run) {
        # Force the canonical Flutter/CMake package path to copy and verify the
        # engine that was just built before Neura starts it with a fresh token.
        & (Join-Path $PSScriptRoot 'Start-Neura.ps1') -Rebuild
    }
} finally {
    Pop-Location
}
