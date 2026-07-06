# polish_pass.ps1
# Phase 1 automation: checkpoint, apply dart fix, re-analyze, save results.
#
# Run from the repo root:
#   Set-Location D:\Vantiger1\neura_os
#   .\polish_pass.ps1

param(
	[string]$RepoRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $RepoRoot

# ── 1. Checkpoint ─────────────────────────────────────────────────────────────
Write-Host "`n[1/4] Checkpointing with git..." -ForegroundColor Cyan
if (Test-Path .git) {
	$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
	git add -A
	git commit -m "chore: pre-polish checkpoint $stamp" --allow-empty 2>&1 | Write-Host
	Write-Host "      Checkpoint committed." -ForegroundColor Green
} else {
	Write-Host "      No .git found — skipping checkpoint (not fatal)." -ForegroundColor Yellow
}

# ── 2. dart fix ───────────────────────────────────────────────────────────────
Write-Host "`n[2/4] Applying dart fix --apply..." -ForegroundColor Cyan
dart fix --apply 2>&1 | Write-Host
Write-Host "      dart fix applied." -ForegroundColor Green

# ── 3. flutter pub get (in case dart fix touched pubspec) ─────────────────────
Write-Host "`n[3/4] Running flutter pub get..." -ForegroundColor Cyan
flutter pub get 2>&1 | Select-Object -Last 3 | Write-Host

# ── 4. flutter analyze ────────────────────────────────────────────────────────
Write-Host "`n[4/4] Running flutter analyze..." -ForegroundColor Cyan
$analyzeOutput = flutter analyze --no-fatal-infos 2>&1
$analyzeOutput | Out-File -FilePath analyze_after_polish.txt -Encoding utf8
$analyzeOutput | Write-Host

$issueCount = ($analyzeOutput | Select-String '^\s+(info|warning|error)\s+-').Count
if ($issueCount -eq 0) {
	Write-Host "`nPhase 1 DONE — 0 issues. Send analyze_after_polish.txt to confirm." -ForegroundColor Green
} else {
	Write-Host "`n$issueCount issue(s) remain. Review analyze_after_polish.txt." -ForegroundColor Yellow
}
