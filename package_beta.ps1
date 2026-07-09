# package_beta.ps1
# Phase 5: validate the Windows release bundle, zip it, write a SHA-256 checksum,
# and generate README_BETA.txt for testers.
#
# Run from the repo root:
#   Set-Location D:\Vantiger1\neura_os
#   .\package_beta.ps1

param(
	[string]$RepoRoot   = $PSScriptRoot,
	[string]$AppVersion = '1.0.0-beta'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $RepoRoot

$bundleDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
$exePath   = Join-Path $bundleDir 'neuro_companion.exe'
$distDir   = Join-Path $RepoRoot 'dist'
$stamp     = (Get-Date -Format 'yyyyMMdd')
$zipName   = "NeuraCompanion_beta_v${AppVersion}_${stamp}.zip"
$zipPath   = Join-Path $distDir $zipName

# ── 1. Validate bundle ────────────────────────────────────────────────────────
Write-Host "`n[1/4] Validating release bundle..." -ForegroundColor Cyan
if (-not (Test-Path $exePath)) {
	Write-Error "neuro_companion.exe not found at $exePath`nRun 'flutter build windows --release' first."
}
Write-Host "      Bundle OK: $bundleDir" -ForegroundColor Green

# ── 2. Write README_BETA.txt ─────────────────────────────────────────────────
Write-Host "`n[2/4] Writing README_BETA.txt..." -ForegroundColor Cyan
$readme = @"
Neura Companion — Windows Beta $AppVersion
==========================================
Thank you for testing!

REQUIREMENTS
  - Windows 10 (1903) or later, 64-bit
  - Microphone recommended for live presence
  - TODO: list any local-model requirement here (e.g. Whisper, Ollama, etc.)

INSTALLATION
  1. Extract this zip to any folder.
  2. Run neuro_companion.exe — no installer needed.
  3. Sign in with the test credentials we sent you, or create a free account.

WHAT TO TEST
  Please focus on one question: does the companion feel present and responsive?
  Speak naturally for 30 seconds and note whether the avatar reacts in real time.

SEND FEEDBACK TO
  TODO: replace this line with your feedback link / email / form URL

KNOWN LIMITATIONS (beta)
  - Avatar animation requires assets/lottie/ or assets/rive/ files; falls back
	to a placeholder circle if those are absent.
  - Google / Apple sign-in not yet wired — use email+password.
  - Mic permission prompt may appear on first launch.

Build date : $stamp
"@
$readmePath = Join-Path $bundleDir 'README_BETA.txt'
$readme | Out-File -FilePath $readmePath -Encoding utf8
Write-Host "      README_BETA.txt written to bundle." -ForegroundColor Green

# ── 3. Zip the bundle ─────────────────────────────────────────────────────────
Write-Host "`n[3/4] Creating zip: $zipName..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$bundleDir\*" -DestinationPath $zipPath
Write-Host "      Zip created: $zipPath" -ForegroundColor Green

# ── 4. SHA-256 checksum ───────────────────────────────────────────────────────
Write-Host "`n[4/4] Computing SHA-256 checksum..." -ForegroundColor Cyan
$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
$checksumLine = "SHA256: $hash  $zipName"
$checksumFile = Join-Path $distDir "$zipName.sha256.txt"
$checksumLine | Out-File -FilePath $checksumFile -Encoding utf8
Write-Host "      $checksumLine" -ForegroundColor Green

Write-Host @"

Phase 5 DONE
  Bundle : $zipPath
  Hash   : $checksumFile

Next steps:
  1. Edit the two TODO lines in $readmePath before shipping.
  2. Send the zip (not the source folder) to 15-25 testers.
"@ -ForegroundColor Cyan
