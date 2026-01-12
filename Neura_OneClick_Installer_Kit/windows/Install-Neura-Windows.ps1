param(
  [string]$ProjectDir = $env:NEURA_PROJECT_DIR
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
  $ProjectDir = Join-Path $PSScriptRoot "..\..\Neura_Companion"
}

Write-Host "Neura Companion — Windows one-click build" -ForegroundColor Cyan
Write-Host "ProjectDir: $ProjectDir"

if (!(Test-Path $ProjectDir)) {
  throw "Project directory not found: $ProjectDir"
}

# Basic sanity checks
flutter --version | Out-Null

Push-Location $ProjectDir

Write-Host "Running flutter clean / pub get / analyze..." -ForegroundColor Yellow
flutter clean
flutter pub get
flutter analyze

Write-Host "Building Windows release..." -ForegroundColor Yellow
flutter build windows --release

$exe = Get-ChildItem -Path ".\build\windows\x64\runner\Release" -Filter "*.exe" | Select-Object -First 1
if ($null -eq $exe) {
  throw "Could not find built .exe in build\windows\x64\runner\Release"
}

Write-Host "Built: $($exe.FullName)" -ForegroundColor Green
Write-Host "Launching Neura..." -ForegroundColor Green
Start-Process $exe.FullName

Pop-Location
Write-Host "Done." -ForegroundColor Cyan
