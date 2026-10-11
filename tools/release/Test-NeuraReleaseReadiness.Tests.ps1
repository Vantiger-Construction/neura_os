#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path ([IO.Path]::GetTempPath()) ("neura-release-gate-" + [guid]::NewGuid())
$current = Join-Path $root 'current'
$previous = Join-Path $root 'previous'
$output = Join-Path $root 'output'
$verifier = Join-Path $PSScriptRoot 'Test-NeuraReleaseReadiness.ps1'

function New-TestPayload([string]$Path, [string]$Marker) {
  New-Item -ItemType Directory -Path (Join-Path $Path 'data') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $Path 'neuro_companion.exe') -Value "exe-$Marker"
  Set-Content -LiteralPath (Join-Path $Path 'flutter_windows.dll') -Value "dll-$Marker"
  Set-Content -LiteralPath (Join-Path $Path 'data/icudtl.dat') -Value "icu-$Marker"
  Set-Content -LiteralPath (Join-Path $Path 'data/app.so') -Value "app-$Marker"
}

try {
  New-TestPayload $current 'new'
  New-TestPayload $previous 'old'
  & $verifier -ArtifactRoot $current -PreviousArtifactRoot $previous -OutputRoot $output

  foreach ($required in @(
    'RELEASE_MANIFEST.json',
    'SHA256SUMS.txt',
    'ROLLBACK_REHEARSAL.json'
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $output $required) -PathType Leaf)) {
      throw "Gate did not create $required"
    }
  }

  $rollback = Get-Content -LiteralPath (Join-Path $output 'ROLLBACK_REHEARSAL.json') -Raw |
    ConvertFrom-Json
  if (-not $rollback.upgradeStaged -or
      -not $rollback.stagedPayloadVerified -or
      -not $rollback.rollbackPayloadVerified) {
    throw 'Rollback rehearsal did not prove all required states.'
  }
  $manifest = Get-Content -LiteralPath (Join-Path $output 'RELEASE_MANIFEST.json') -Raw |
    ConvertFrom-Json
  if (-not $manifest.userInitiatedInstallOnly) {
    throw 'Release manifest must preserve user-initiated install policy.'
  }

  $broken = Join-Path $root 'broken'
  New-Item -ItemType Directory -Path $broken | Out-Null
  Set-Content -LiteralPath (Join-Path $broken 'neuro_companion.exe') -Value 'incomplete'
  $failedClosed = $false
  try {
    & $verifier -ArtifactRoot $broken -OutputRoot (Join-Path $root 'broken-output')
  } catch {
    $failedClosed = $true
  }
  if (-not $failedClosed) { throw 'Incomplete payload did not fail closed.' }

  Write-Host 'Release-readiness contract tests passed.'
} finally {
  if (Test-Path -LiteralPath $root) {
    Remove-Item -LiteralPath $root -Recurse -Force
  }
}
