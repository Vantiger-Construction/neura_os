#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$BuildAndroid,
    [switch]$SkipTests,
    [switch]$SkipLaunchSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LaunchSmokeSuccessExitCode = 73

function Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Good([string]$Text) { Write-Host "[OK] $Text" -ForegroundColor Green }
function Run([scriptblock]$Command, [string]$Failure) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Failure (exit $LASTEXITCODE)" }
}

function Resolve-PubspecVersion([string]$PubspecPath) {
    $match = Select-String -LiteralPath $PubspecPath `
        -Pattern '^\s*version:\s*["'']?([^\s#"'']+)' |
        Select-Object -First 1
    if (-not $match) {
        throw 'Could not read the app version from pubspec.yaml.'
    }
    return $match.Matches[0].Groups[1].Value
}

function Resolve-WindowsExecutableName([string]$ProjectRoot) {
    $cmakePath = Join-Path $ProjectRoot 'windows\CMakeLists.txt'
    if (-not (Test-Path -LiteralPath $cmakePath -PathType Leaf)) {
        throw "Windows CMake project is missing: $cmakePath"
    }
    $match = Select-String -LiteralPath $cmakePath `
        -Pattern '^\s*set\(BINARY_NAME\s+["'']?([^\s\)"'']+)' |
        Select-Object -First 1
    if (-not $match) {
        throw 'Could not resolve BINARY_NAME from windows\CMakeLists.txt.'
    }
    return "$($match.Matches[0].Groups[1].Value).exe"
}

function Find-VcRuntimeFile([string]$Name) {
    $programRoots = New-Object System.Collections.Generic.List[string]
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $programRoots.Add($programFilesX86)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $programRoots.Add($env:ProgramFiles)
    }

    $runtimeFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($programRoot in $programRoots) {
        # Any Visual Studio layout: 2019/2022 use year folders, 2026+ uses
        # major-version folders (e.g. "18"), as on current windows-latest.
        $pattern = Join-Path $programRoot "Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT\$Name"
        Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            ForEach-Object { $runtimeFiles.Add($_) }
    }
    $selected = $runtimeFiles | Sort-Object -Property FullName -Descending |
        Select-Object -First 1
    if ($selected) { return $selected.FullName }

    # Fall back to the system-installed x64 VC++ runtime.
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $systemCopy = Join-Path $env:SystemRoot "System32\$Name"
        if (Test-Path -LiteralPath $systemCopy -PathType Leaf) {
            return $systemCopy
        }
    }
    return $null
}

function Ensure-AppLocalVcRuntime([string]$ReleaseRoot) {
    foreach ($runtimeName in @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )) {
        $destination = Join-Path $ReleaseRoot $runtimeName
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            $source = Find-VcRuntimeFile $runtimeName
            if (-not $source) {
                throw (
                    'Visual C++ x64 redistributable file was not found ' +
                    "in a Visual Studio VC Redist directory: $runtimeName"
                )
            }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
}

function Assert-WindowsRuntimePayload(
    [string]$ReleaseRoot,
    [string]$ExecutableName
) {
    $requiredFiles = @(
        (Join-Path $ReleaseRoot $ExecutableName),
        (Join-Path $ReleaseRoot 'flutter_windows.dll'),
        (Join-Path $ReleaseRoot 'neura_swarm.dll'),
        (Join-Path $ReleaseRoot 'msvcp140.dll'),
        (Join-Path $ReleaseRoot 'vcruntime140.dll'),
        (Join-Path $ReleaseRoot 'vcruntime140_1.dll'),
        (Join-Path $ReleaseRoot 'data\icudtl.dat'),
        (Join-Path $ReleaseRoot 'data\app.so')
    )
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Windows runtime payload is incomplete; missing: $requiredFile"
        }
        if ((Get-Item -LiteralPath $requiredFile).Length -le 0) {
            throw "Windows runtime payload contains an empty file: $requiredFile"
        }
    }

    $flutterAssets = Join-Path $ReleaseRoot 'data\flutter_assets'
    if (-not (Test-Path -LiteralPath $flutterAssets -PathType Container)) {
        throw "Windows runtime payload is incomplete; missing: $flutterAssets"
    }
    if (-not (Get-ChildItem -LiteralPath $flutterAssets -File -Recurse |
        Select-Object -First 1)) {
        throw "Windows Flutter asset directory is empty: $flutterAssets"
    }

    $emptyDll = Get-ChildItem -LiteralPath $ReleaseRoot -Filter '*.dll' -File -Recurse |
        Where-Object { $_.Length -le 0 } |
        Select-Object -First 1
    if ($emptyDll) {
        throw "Windows runtime payload contains an empty DLL: $($emptyDll.FullName)"
    }
}

function Invoke-WindowsLaunchSmokeTest(
    [string]$ExecutablePath,
    [int]$TimeoutSeconds = 15
) {
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        throw "Launch smoke-test executable is missing: $ExecutablePath"
    }
    if ($TimeoutSeconds -lt 1) {
        throw 'Launch smoke-test timeout must be at least one second.'
    }

    $process = $null
    $started = $false
    $passed = $false
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $ExecutablePath
        $startInfo.Arguments = '--launch-smoke-test'
        $startInfo.WorkingDirectory = Split-Path -Parent $ExecutablePath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $false

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'Windows did not start the packaged executable.'
        }
        $started = $true
        $smokePid = $process.Id
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            throw "Launch self-test PID $smokePid did not self-exit within $TimeoutSeconds seconds."
        }
        if ($process.ExitCode -ne $LaunchSmokeSuccessExitCode) {
            throw "Launch self-test exited with code $($process.ExitCode); expected sentinel $LaunchSmokeSuccessExitCode."
        }
        $passed = $true
    } finally {
        if ($process) {
            try {
                if ($started) {
                    $process.Refresh()
                    if (-not $passed -and -not $process.HasExited) {
                        # Stop only the exact process created for this failed
                        # or timed-out test. Never name-match running Neura.
                        Stop-Process -Id $process.Id -Force -ErrorAction Stop
                        $process.WaitForExit(5000) | Out-Null
                    }
                }
            } finally {
                $process.Dispose()
            }
        }
    }
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
    $secretHits = Get-ChildItem -LiteralPath $Root -File -Recurse |
        Where-Object {
            $_.FullName -notmatch '[\\/](build|\.dart_tool|\.git|dist|upgrade_backups)[\\/]' -and
            $_.Length -lt 5MB
        } |
        Select-String -Pattern 'sk-ant-[A-Za-z0-9_-]{20,}' -ErrorAction SilentlyContinue
    if ($secretHits) {
        $paths = ($secretHits | Select-Object -ExpandProperty Path -Unique) -join "`n  "
        throw "Possible provider secret found. Revoke/remove it before building:`n  $paths"
    }
    Good 'Secret gate passed'

    Step 'Resolving Flutter packages'
    Run { flutter pub get } 'flutter pub get failed'

    Step 'Formatting Dart sources'
    Run { dart format lib test } 'Dart formatting failed'
    Run {
        dart format --output=none --set-exit-if-changed lib test
    } 'Dart format verification failed'

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

    $releaseVersion = Resolve-PubspecVersion (Join-Path $Root 'pubspec.yaml')
    $safeReleaseVersion = $releaseVersion -replace '[^0-9A-Za-z._-]', '_'
    $executableName = Resolve-WindowsExecutableName $Root
    $windowsRelease = Join-Path $Root 'build\windows\x64\runner\Release'
    Ensure-AppLocalVcRuntime $windowsRelease
    Assert-WindowsRuntimePayload $windowsRelease $executableName

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dist = Join-Path $Root "dist\Neura_Companion_${safeReleaseVersion}_$stamp"
    New-Item -ItemType Directory -Force -Path $dist | Out-Null

    $localBrainExe = Join-Path $Root 'rust\target\release\neura_api.exe'
    if (-not (Test-Path -LiteralPath $localBrainExe -PathType Leaf) -or
        (Get-Item -LiteralPath $localBrainExe).Length -le 0) {
        throw "Neura local-brain executable is missing or empty: $localBrainExe"
    }
    Copy-Item -LiteralPath $windowsRelease -Destination (Join-Path $dist 'app') -Recurse
    Copy-Item -LiteralPath $localBrainExe -Destination (Join-Path $dist 'app\neura_api.exe')
    Assert-WindowsRuntimePayload (Join-Path $dist 'app') $executableName

    $packagedExe = Join-Path $dist "app\$executableName"
    if ($SkipLaunchSmokeTest) {
        $launchSmokeStatus = 'skipped by request'
        Write-Warning 'Launch smoke test skipped explicitly with -SkipLaunchSmokeTest.'
    } else {
        Step 'Running packaged launch self-test'
        Invoke-WindowsLaunchSmokeTest $packagedExe 15
        $launchSmokeStatus = 'passed'
        Good "Packaged executable self-exited with smoke sentinel $LaunchSmokeSuccessExitCode"
    }

    Copy-Item -LiteralPath (Join-Path $Root 'NEURA_CONSOLIDATED_UPGRADES.md') -Destination $dist
    Copy-Item -LiteralPath (Join-Path $Root 'CHANGELOG_INTELLIGENCE_v1.3.0.md') -Destination $dist
    Copy-Item -LiteralPath (Join-Path $Root 'docs\INTELLIGENCE_FABRIC_v1.3.md') -Destination $dist
    Copy-Item -LiteralPath (Join-Path $Root 'docs\PrivacyPolicy.md') -Destination $dist
    Copy-Item -LiteralPath (Join-Path $Root 'docs\TermsOfService.md') -Destination $dist

    $launcher = @'
@echo off
setlocal
set "HERE=%~dp0"
pushd "%HERE%" >nul 2>&1 || exit /b 1
start "Neura Local Brain" /min "%HERE%neura_api.exe"
timeout /t 2 /nobreak >nul
start "Neura Companion" "%HERE%__NEURA_EXECUTABLE__%"
popd
endlocal
'@
    $launcher = $launcher.Replace('__NEURA_EXECUTABLE__', $executableName)
    Set-Content -LiteralPath (Join-Path $dist 'app\START_NEURA.bat') -Value $launcher -Encoding ASCII

    $troubleshooting = @"
Neura Companion $releaseVersion - Startup and Diagnostics

If Neura closes during startup:
1. Keep the entire app folder together. Do not move only $executableName.
2. Run $executableName again, then collect the newest records from these paths:

Native Windows crash/startup vault:
  %TEMP%\neura_error_vault.jsonl
  Rotated copies: neura_error_vault.jsonl.1 through .3

Early Dart/bootstrap log:
  %LOCALAPPDATA%\Neura OS\Logs\bootstrap_crash.ndjson
  Rotated copy: bootstrap_crash.ndjson.old

Application log:
  %APPDATA%\com.neurocompanion\neuro_companion\neura\logs\neura.log.ndjson
  Rotated copies: neura.log.ndjson.1 and neura.log.ndjson.2

The Diagnostics screen can view, export, and clear privacy-filtered logs when
the app reaches its recovery UI. Logs are local, bounded, rotated, and redact
known credential and personal-data patterns. Review any file before sharing it.

Build verification:
  Runtime payload: passed
  Launch self-test: $launchSmokeStatus
"@
    Set-Content -LiteralPath (Join-Path $dist 'TROUBLESHOOTING.txt') `
        -Value $troubleshooting -Encoding UTF8

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
