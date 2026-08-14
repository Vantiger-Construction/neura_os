#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$BuildAndroid,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Good([string]$Text) { Write-Host "[OK] $Text" -ForegroundColor Green }
function Run([scriptblock]$Command, [string]$Failure) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Failure (exit $LASTEXITCODE)" }
}

$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not (Test-Path -LiteralPath (Join-Path $Root 'pubspec.yaml'))) {
    throw "Not a Neura Flutter root: $Root"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is missing from PATH.'
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw 'Rust/cargo is missing from PATH.'
}

Push-Location $Root
try {
    Step 'Checking for embedded Anthropic secrets'
    $matches = Get-ChildItem -LiteralPath $Root -File -Recurse |
        Where-Object {
            $_.FullName -notmatch '[\\/](build|\.dart_tool|\.git|dist|upgrade_backups)[\\/]' -and
            $_.Length -lt 5MB
        } |
        Select-String -Pattern 'sk-ant-[A-Za-z0-9_-]{20,}' -ErrorAction SilentlyContinue
    if ($matches) {
        $paths = ($matches | Select-Object -ExpandProperty Path -Unique) -join "`n  "
        throw "Possible provider secret found. Revoke/remove it before building:`n  $paths"
    }
    Good 'Secret gate passed'

    Step 'Resolving Flutter packages'
    Run { flutter pub get } 'flutter pub get failed'

    Step 'Formatting and testing Rust'
    Run { cargo fmt --manifest-path rust\Cargo.toml -- --check } 'cargo fmt check failed'
    Run { cargo test --manifest-path rust\Cargo.toml } 'Rust tests failed'

    Step 'Building Neura local brain'
    Run { cargo build --release --bin neura_api --manifest-path rust\Cargo.toml } 'Local brain build failed'

    Step 'Analyzing Flutter'
    Run { flutter analyze --no-fatal-warnings --no-fatal-infos } 'Flutter analysis failed'
    if (-not $SkipTests) {
        Step 'Testing Flutter'
        Run { flutter test } 'Flutter tests failed'
    }

    Step 'Building Windows release'
    Run { flutter build windows --release } 'Windows build failed'

    if ($BuildAndroid) {
        Step 'Building Android app bundle'
        Run { flutter build appbundle --release } 'Android app bundle failed'
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dist = Join-Path $Root "dist\Neura_Companion_1.2.0_$stamp"
    New-Item -ItemType Directory -Force -Path $dist | Out-Null

    $windowsRelease = Join-Path $Root 'build\windows\x64\runner\Release'
    Copy-Item -LiteralPath $windowsRelease -Destination (Join-Path $dist 'app') -Recurse
    Copy-Item -LiteralPath (Join-Path $Root 'rust\target\release\neura_api.exe') -Destination (Join-Path $dist 'app\neura_api.exe')
    Copy-Item -LiteralPath (Join-Path $Root 'NEURA_CONSOLIDATED_UPGRADES.md') -Destination $dist
    Copy-Item -LiteralPath (Join-Path $Root 'docs\PrivacyPolicy.md') -Destination $dist
    Copy-Item -LiteralPath (Join-Path $Root 'docs\TermsOfService.md') -Destination $dist

    $launcher = @'
@echo off
setlocal
set "HERE=%~dp0"
start "Neura Local Brain" /min "%HERE%neura_api.exe"
timeout /t 2 /nobreak >nul
start "Neura Companion" "%HERE%neuro_companion.exe"
endlocal
'@
    Set-Content -LiteralPath (Join-Path $dist 'app\START_NEURA.bat') -Value $launcher -Encoding ASCII

    if ($BuildAndroid) {
        $bundle = Join-Path $Root 'build\app\outputs\bundle\release\app-release.aab'
        if (Test-Path -LiteralPath $bundle) {
            Copy-Item -LiteralPath $bundle -Destination (Join-Path $dist 'Neura-Companion-Android.aab')
        }
    }

    $zip = "$dist.zip"
    Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $zip -CompressionLevel Optimal
    Good "Complete portable build: $zip"
} finally {
    Pop-Location
}
