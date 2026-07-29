[CmdletBinding()]
param(
    [string]$Root,
    [switch]$SkipRepair,
    [switch]$SkipTests,
    [switch]$BuildWindows,
    [switch]$BuildApk
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repair = Join-Path $PSScriptRoot 'Neura-DartRepair.ps1'
if (-not $SkipRepair) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $repair -Root $Root -RunAnalyzer -AutoFixStringLiterals
    if ($LASTEXITCODE -ne 0) { throw "Repair/analyze gate failed with exit code $LASTEXITCODE." }
}
if (-not $Root) { $Root = (Get-Location).Path }
Push-Location $Root
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
    if (-not $SkipTests) {
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
    }
    if ($BuildWindows) {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    }
    if ($BuildApk) {
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
    }
} finally { Pop-Location }
Write-Host 'Neura build pipeline completed successfully.' -ForegroundColor Green
