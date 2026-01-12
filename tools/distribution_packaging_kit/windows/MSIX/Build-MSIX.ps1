param(
  [string]$ProjectDir = $env:NEURA_PROJECT_DIR
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
  $ProjectDir = Join-Path $PSScriptRoot "..\..\..\Neura_Companion"
}

Write-Host "Neura — MSIX packaging" -ForegroundColor Cyan
Write-Host "ProjectDir: $ProjectDir"

if (!(Test-Path $ProjectDir)) { throw "Project directory not found: $ProjectDir" }

flutter --version | Out-Null

Push-Location $ProjectDir

Write-Host "Clean/Get/Analyze..." -ForegroundColor Yellow
flutter clean
flutter pub get
flutter analyze

Write-Host "Build Windows release..." -ForegroundColor Yellow
flutter build windows --release

Write-Host "Ensure msix package exists..." -ForegroundColor Yellow
# Install msix package if missing (idempotent)
flutter pub add msix | Out-Null

Write-Host "Build MSIX..." -ForegroundColor Yellow
flutter pub run msix:create

Write-Host "MSIX build complete." -ForegroundColor Green
Write-Host "Look under: build\\windows\\x64\\runner\\Release and build\\msix\\" -ForegroundColor Green

Pop-Location
