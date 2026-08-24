#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [switch]$ForcePubGet,
    [switch]$SkipTests,
    [switch]$BuildWindows,
    [ValidateRange(1, 32)]
    [int]$TestConcurrency = [Math]::Min([Environment]::ProcessorCount, 8)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Command
    )

    Write-Host "`n=== $Label ===" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Get-DependencyFingerprint {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $inputs = @('pubspec.yaml', 'pubspec.lock') |
        ForEach-Object { Join-Path $ProjectRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    if ($inputs.Count -eq 0) { return '' }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = foreach ($file in $inputs) {
            [System.IO.File]::ReadAllBytes($file)
        }
        $all = [System.Collections.Generic.List[byte]]::new()
        foreach ($chunk in $bytes) { $all.AddRange($chunk) }
        return ([BitConverter]::ToString($sha.ComputeHash($all.ToArray()))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-AuthoredWindowsRunner {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $rolePath = Join-Path $ProjectRoot 'windows\runner\neura_window_role.cpp'
    $cmakePath = Join-Path $ProjectRoot 'windows\runner\CMakeLists.txt'
    $flutterWindowPath = Join-Path $ProjectRoot 'windows\runner\flutter_window.cpp'

    foreach ($required in @($rolePath, $cmakePath, $flutterWindowPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Authored Windows runner file is missing: $required"
        }
    }

    $roleSource = Get-Content -LiteralPath $rolePath -Raw
    $cmake = Get-Content -LiteralPath $cmakePath -Raw
    $flutterWindow = Get-Content -LiteralPath $flutterWindowPath -Raw

    if (-not $roleSource.Contains('neura/window_role')) {
        throw 'Authored Windows runner is missing the neura/window_role channel.'
    }
    if (-not $cmake.Contains('"neura_window_role.cpp"')) {
        throw 'Authored Windows runner does not compile neura_window_role.cpp.'
    }
    if (-not $flutterWindow.Contains('window_role_ = std::make_unique<NeuraWindowRole>')) {
        throw 'Authored Windows runner does not register NeuraWindowRole before plugins.'
    }
}

$Root = (Resolve-Path -LiteralPath $Root).Path
$pubspec = Join-Path $Root 'pubspec.yaml'
if (-not (Test-Path -LiteralPath $pubspec -PathType Leaf)) {
    throw "No pubspec.yaml found at $Root"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available on PATH.'
}

$cacheDir = Join-Path $Root '.dart_tool\neura'
$fingerprintFile = Join-Path $cacheDir 'dependency_fingerprint.txt'
$currentFingerprint = Get-DependencyFingerprint -ProjectRoot $Root
$previousFingerprint = if (Test-Path -LiteralPath $fingerprintFile) {
    (Get-Content -LiteralPath $fingerprintFile -Raw).Trim()
} else { '' }

Push-Location $Root
try {
    $packagesFile = Join-Path $Root '.dart_tool\package_config.json'
    $needsPubGet = $ForcePubGet -or
        -not (Test-Path -LiteralPath $packagesFile -PathType Leaf) -or
        $currentFingerprint -ne $previousFingerprint

    if ($needsPubGet) {
        Invoke-Checked 'flutter pub get' { flutter pub get }
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
        Set-Content -LiteralPath $fingerprintFile -Value $currentFingerprint -NoNewline
    } else {
        Write-Host "`n=== flutter pub get ===" -ForegroundColor Cyan
        Write-Host 'Skipped: dependency inputs are unchanged.' -ForegroundColor DarkGray
    }

    Invoke-Checked 'dart format check' {
        dart format --output=none --set-exit-if-changed lib test
    }

    Invoke-Checked 'flutter analyze' {
        flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
    }

    if ($BuildWindows) {
        Write-Host "`n=== authored Windows runner contract ===" -ForegroundColor Cyan
        Assert-AuthoredWindowsRunner -ProjectRoot $Root
    }

    if (-not $SkipTests) {
        Invoke-Checked 'startup state matrix' {
            flutter test --no-pub --timeout 60s `
                test/startup/startup_platform_policy_test.dart `
                test/startup/native_speech_safe_mode_test.dart `
                test/startup/neura_error_pipeline_test.dart
        }

        Invoke-Checked 'recovery boundary test' {
            flutter test --no-pub --timeout 30s `
                test/startup/neura_error_boundary_test.dart
        }

        Invoke-Checked "flutter test (concurrency=$TestConcurrency)" {
            flutter test --no-pub --concurrency $TestConcurrency
        }
    }

    if ($BuildWindows) {
        Invoke-Checked 'flutter build windows --release' {
            flutter build windows --release --no-pub
        }
    }
} finally {
    Pop-Location
}

Write-Host "`nNeura fast validation completed successfully." -ForegroundColor Green
