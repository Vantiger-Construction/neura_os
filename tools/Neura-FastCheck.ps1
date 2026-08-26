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
        $all = [System.Collections.Generic.List[byte]]::new()
        foreach ($file in $inputs) {
            # PowerShell normally enumerates byte arrays written to the
            # pipeline. Keep each payload strongly typed so AddRange receives
            # IEnumerable[byte] rather than one scalar byte at a time.
            [byte[]]$chunk = [System.IO.File]::ReadAllBytes($file)
            $all.AddRange($chunk)
        }
        return ([BitConverter]::ToString($sha.ComputeHash($all.ToArray()))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-NoMergeMarkers {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $matches = @()
    foreach ($relativeRoot in @('lib', 'test')) {
        $candidate = Join-Path $ProjectRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }

        $dartFiles = Get-ChildItem -LiteralPath $candidate -File -Recurse |
            Where-Object { $_.Extension -eq '.dart' }
        if ($dartFiles) {
            $matches += $dartFiles |
                Select-String -Pattern '^(<<<<<<<|=======|>>>>>>>)'
        }
    }

    if ($matches.Count -gt 0) {
        $matches |
            Select-Object -First 20 |
            ForEach-Object {
                Write-Host (
                    '{0}:{1}: {2}' -f $_.Path, $_.LineNumber, $_.Line
                ) -ForegroundColor Red
            }
        throw 'Unresolved merge markers are committed in lib or test.'
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

function Assert-PackagedWindowsLaunch {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $release = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
    $exe = Join-Path $release 'neuro_companion.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Expected Windows executable was not produced: $exe"
    }

    foreach ($runtimeName in @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )) {
        $destination = Join-Path $release $runtimeName
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            continue
        }

        $matches = @()
        foreach ($programRoot in @(
            ${env:ProgramFiles(x86)},
            $env:ProgramFiles
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
            $matches += Get-ChildItem -Path (
                Join-Path $programRoot (
                    "Microsoft Visual Studio\*\*\VC\Redist\MSVC\*" +
                    "\x64\Microsoft.VC*.CRT\$runtimeName"
                )
            ) -File -ErrorAction SilentlyContinue
        }

        $source = $matches |
            Sort-Object -Property FullName -Descending |
            Select-Object -First 1
        if (-not $source) {
            throw "Visual C++ x64 runtime was not found: $runtimeName"
        }
        Copy-Item -LiteralPath $source.FullName -Destination $destination
    }

    foreach ($required in @(
        $exe,
        (Join-Path $release 'flutter_windows.dll'),
        (Join-Path $release 'neura_swarm.dll'),
        (Join-Path $release 'msvcp140.dll'),
        (Join-Path $release 'vcruntime140.dll'),
        (Join-Path $release 'vcruntime140_1.dll'),
        (Join-Path $release 'data\icudtl.dat'),
        (Join-Path $release 'data\app.so')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf) -or
            (Get-Item -LiteralPath $required).Length -le 0) {
            throw "Windows runtime payload is incomplete: $required"
        }
    }

    $flutterAssets = Join-Path $release 'data\flutter_assets'
    if (-not (Test-Path -LiteralPath $flutterAssets -PathType Container) -or
        -not (Get-ChildItem -LiteralPath $flutterAssets -File -Recurse |
            Select-Object -First 1)) {
        throw "Windows Flutter assets are missing or empty: $flutterAssets"
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $exe
    $startInfo.Arguments = '--launch-smoke-test'
    $startInfo.WorkingDirectory = $release
    $startInfo.UseShellExecute = $false

    $smoke = New-Object System.Diagnostics.Process
    $smoke.StartInfo = $startInfo
    $started = $false
    try {
        if (-not $smoke.Start()) {
            throw 'Windows did not start the packaged executable.'
        }
        $started = $true
        if (-not $smoke.WaitForExit(15000)) {
            throw 'Packaged launch self-test did not self-exit within 15 seconds.'
        }
        if ($smoke.ExitCode -ne 73) {
            throw (
                "Packaged launch self-test exited with code " +
                "$($smoke.ExitCode); expected sentinel 73."
            )
        }
    } finally {
        if ($started) {
            $smoke.Refresh()
            if (-not $smoke.HasExited) {
                Stop-Process -Id $smoke.Id -Force -ErrorAction Stop
            }
        }
        $smoke.Dispose()
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
    Write-Host "`n=== unresolved merge marker check ===" -ForegroundColor Cyan
    Assert-NoMergeMarkers -ProjectRoot $Root

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

    Invoke-Checked 'flutter analyze --fatal-infos' {
        flutter analyze --no-pub --fatal-infos
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

        Write-Host "`n=== packaged Windows launch self-test ===" -ForegroundColor Cyan
        Assert-PackagedWindowsLaunch -ProjectRoot $Root
    }
} finally {
    Pop-Location
}

Write-Host "`nNeura fast validation completed successfully." -ForegroundColor Green
