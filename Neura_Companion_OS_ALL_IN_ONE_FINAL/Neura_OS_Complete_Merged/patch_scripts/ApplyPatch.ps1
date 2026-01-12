param(
  [Parameter(Mandatory=$true)][string]$Target
)

Write-Host "Applying Neura OS Patch v8…" -ForegroundColor Cyan

$src = Join-Path $PSScriptRoot "..\neura_os"
if (!(Test-Path $src)) { throw "Patch source not found: $src" }

$targetResolved = (Resolve-Path $Target).Path

# Accept either:
# 1) the Flutter project root (contains pubspec.yaml)
# 2) a parent folder that contains neura_os\pubspec.yaml
$dest = $null
if (Test-Path (Join-Path $targetResolved "pubspec.yaml")) {
  $dest = $targetResolved
} elseif (Test-Path (Join-Path $targetResolved "neura_os\pubspec.yaml")) {
  $dest = Join-Path $targetResolved "neura_os"
}

if ($null -eq $dest) {
  throw "Target must be the Flutter project root (pubspec.yaml) or a folder containing neura_os\\pubspec.yaml. Given: $targetResolved"
}

Write-Host "Copying files into: $dest"
Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force

Write-Host "Done." -ForegroundColor Green
Write-Host "Next:" -ForegroundColor Green
Write-Host "  cd $dest"
Write-Host "  flutter pub get"
Write-Host "  flutter run"
