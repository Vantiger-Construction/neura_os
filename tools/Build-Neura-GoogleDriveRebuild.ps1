#Requires -Version 5.1
<#
.SYNOPSIS
Builds the recovered Neura Flutter source from an isolated staging copy.

.DESCRIPTION
This script is intended for the Google Drive recovery package layout:

  <PackageRoot>\source\rebuilt_flutter
  <PackageRoot>\tools\Build-Neura-GoogleDriveRebuild.ps1
  <PackageRoot>\dist

If -SourceRoot is not supplied, source\rebuilt_flutter is preferred. When that
snapshot is absent and PackageRoot itself is a Flutter project, the canonical
root project is used as a safe fallback. The source tree is never built in
place: it is copied into a timestamped staging directory under LOCALAPPDATA.

The build is fail-fast:
  1. Resolve Flutter and validate the source.
  2. Copy source into isolated staging.
  3. Generate missing Windows/Android platform scaffolds.
  4. Restore authored source files.
  5. Run flutter pub get.
  6. Require flutter analyze to succeed.
  7. Run flutter test unless -SkipTests.
  8. Build Windows x64 release.
  9. Optionally build an Android APK.
 10. Package outputs and SHA-256 checksums under dist.

This script does not merge historical forks, modify the original recovered
snapshot, create an installer, or prove end-user data recovery.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 -Yes

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -PackageRoot "D:\NeuraRecovery" `
  -FlutterPath "C:\src\flutter\bin\flutter.bat" `
  -BuildAndroid
#>
[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SourceRoot,
    [string]$FlutterPath,
    [string]$BuildName = '1.1.0',
    [int]$BuildNumber = 2,
    [switch]$SkipTests,
    [switch]$BuildAndroid,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Cyan) {
    Write-Host $Message -ForegroundColor $Color
}

function Stop-Build([string]$Message, [int]$Code = 1) {
    Step ''
    Step "[X] $Message" Red
    exit $Code
}

function Resolve-FlutterExecutable([string]$RequestedPath) {
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidate = [Environment]::ExpandEnvironmentVariables($RequestedPath)

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }

        $batCandidate = Join-Path $candidate 'flutter.bat'
        if (Test-Path -LiteralPath $batCandidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $batCandidate).Path
        }
    }

    foreach ($commandName in @('flutter.bat', 'flutter')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }

    $common = @(
        (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'),
        (Join-Path $env:USERPROFILE 'development\flutter\bin\flutter.bat'),
        'C:\src\flutter\bin\flutter.bat',
        'C:\flutter\bin\flutter.bat',
        'D:\flutter\bin\flutter.bat'
    )

    return ($common |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1)
}

function Copy-RecoverySource([string]$From, [string]$To) {
    $excludedNames = @('.git', '.dart_tool', '.neura_repair', '.pub', 'build', 'dist', '.idea', '.vs')

    Get-ChildItem -LiteralPath $From -Force |
        Where-Object { $excludedNames -notcontains $_.Name } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $To -Recurse -Force
        }
}

function Invoke-FlutterLogged(
    [string]$FlutterExecutable,
    [string[]]$Arguments,
    [string]$LogPath,
    [string]$FailureMessage,
    [int]$FailureCode
) {
    & $FlutterExecutable @Arguments *>&1 |
        Tee-Object -FilePath $LogPath -Append |
        Out-Host

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Stop-Build "$FailureMessage (exit code $exitCode)." $FailureCode
    }
}

try {
    $PackageRoot = (Resolve-Path -LiteralPath $PackageRoot -ErrorAction Stop).Path
} catch {
    Stop-Build "Package root not found: $PackageRoot"
}

if ($BuildNumber -lt 1) {
    Stop-Build 'BuildNumber must be 1 or greater.'
}

$preferredRecoveredSource = Join-Path $PackageRoot 'source\rebuilt_flutter'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    if (Test-Path -LiteralPath (Join-Path $preferredRecoveredSource 'pubspec.yaml') -PathType Leaf) {
        $SourceRoot = $preferredRecoveredSource
        $sourceMode = 'recovered_snapshot'
    } elseif (
        (Test-Path -LiteralPath (Join-Path $PackageRoot 'pubspec.yaml') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $PackageRoot 'lib\main.dart') -PathType Leaf)
    ) {
        $SourceRoot = $PackageRoot
        $sourceMode = 'canonical_repository_root'
    } else {
        Stop-Build "No Flutter source was found. Expected: $preferredRecoveredSource (or pass -SourceRoot)."
    }
} else {
    try {
        $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
    } catch {
        Stop-Build "Source root not found: $SourceRoot"
    }
    $sourceMode = 'explicit_source_root'
}

if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'pubspec.yaml') -PathType Leaf)) {
    Stop-Build "Flutter pubspec is missing: $SourceRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'lib\main.dart') -PathType Leaf)) {
    Stop-Build "Flutter entrypoint is missing: $(Join-Path $SourceRoot 'lib\main.dart')"
}

$flutter = Resolve-FlutterExecutable $FlutterPath
if (-not $flutter) {
    Stop-Build 'Flutter was not found. Install Flutter stable, add flutter\bin to PATH, then run this launcher again.' 10
}

$pubspecName = 'unknown'
$nameMatch = Select-String -LiteralPath (Join-Path $SourceRoot 'pubspec.yaml') -Pattern '^\s*name:\s*(.+?)\s*$' |
    Select-Object -First 1
if ($nameMatch) {
    $pubspecName = $nameMatch.Matches[0].Groups[1].Value.Trim()
}
$dartCount = @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'lib') -Recurse -File -Filter '*.dart').Count

$Dist = Join-Path $PackageRoot 'dist'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$WorkRoot = Join-Path $env:LOCALAPPDATA "NeuraCompanion\Builds\DriveRebuild_$Stamp"
$WorkSource = Join-Path $WorkRoot 'source'
$Preserve = Join-Path $WorkRoot 'preserve'
New-Item -ItemType Directory -Path $WorkSource -Force | Out-Null
New-Item -ItemType Directory -Path $Preserve -Force | Out-Null
New-Item -ItemType Directory -Path $Dist -Force | Out-Null
$Log = Join-Path $Dist "DriveRebuild_build_$Stamp.log"

Step ''
Step 'NEURA COMPANION - GOOGLE DRIVE REBUILD' Magenta
Step "  Package      : $PackageRoot"
Step "  Source       : $SourceRoot"
Step "  Source mode  : $sourceMode"
Step "  Pubspec name : $pubspecName"
Step "  Dart files   : $dartCount"
Step "  Staging      : $WorkSource"
Step "  Flutter      : $flutter"
Step "  Log          : $Log"
Step ''

if ($pubspecName -ne 'neuro_companion') {
    Step "  [!] Expected the canonical package name 'neuro_companion'." Yellow
    Step "      Continue only if this recovered snapshot is intentional." Yellow
    Step ''
}

if (-not $Yes) {
    $answer = Read-Host 'Build this recovered native source now? (Y/n)'
    if ($answer -match '^(?i:n|no)$') { exit 0 }
}

# Build from an isolated copy so the recovered snapshots remain untouched.
Copy-RecoverySource $SourceRoot $WorkSource

# Remove nested generated caches that may have been copied inside platform folders.
foreach ($relativeCache in @(
    'android\.gradle',
    'ios\Flutter\Flutter.framework',
    'macos\Flutter\ephemeral',
    'windows\flutter\ephemeral',
    'linux\flutter\ephemeral'
)) {
    $cachePath = Join-Path $WorkSource $relativeCache
    if (Test-Path -LiteralPath $cachePath) {
        Remove-Item -LiteralPath $cachePath -Recurse -Force
    }
}

# Preserve authored files because flutter create may regenerate template files
# while adding missing platform scaffolding.
foreach ($name in @('lib', 'test', 'assets')) {
    $candidate = Join-Path $WorkSource $name
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        Copy-Item -LiteralPath $candidate -Destination (Join-Path $Preserve $name) -Recurse -Force
    }
}
foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml', 'README.md')) {
    $candidate = Join-Path $WorkSource $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        Copy-Item -LiteralPath $candidate -Destination (Join-Path $Preserve $name) -Force
    }
}

$Zip = $null
$Hash = $null
$ApkOut = $null
$ApkHash = $null
$Release = $null
$Exe = $null
$safeBuildName = $BuildName -replace '[^0-9A-Za-z._-]', '_'

Push-Location $WorkSource
try {
    Step '[1/7] Recording Flutter toolchain'
    Invoke-FlutterLogged $flutter @('--version') $Log 'Flutter could not start' 11

    Step '[2/7] Creating missing Windows and Android platform scaffolds'
    Invoke-FlutterLogged $flutter @(
        'create',
        '.',
        '--project-name',
        'neura_drive_rebuild',
        '--org',
        'com.vantiger.neura',
        '--platforms',
        'windows,android'
    ) $Log 'flutter create failed' 12

    foreach ($name in @('lib', 'test', 'assets')) {
        $generated = Join-Path $WorkSource $name
        $authored = Join-Path $Preserve $name

        if (Test-Path -LiteralPath $generated) {
            Remove-Item -LiteralPath $generated -Recurse -Force
        }
        if (Test-Path -LiteralPath $authored -PathType Container) {
            Copy-Item -LiteralPath $authored -Destination $generated -Recurse -Force
        }
    }

    foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml', 'README.md')) {
        $authored = Join-Path $Preserve $name
        if (Test-Path -LiteralPath $authored -PathType Leaf) {
            Copy-Item -LiteralPath $authored -Destination (Join-Path $WorkSource $name) -Force
        }
    }

    Step '[3/7] Restoring dependencies'
    Invoke-FlutterLogged $flutter @('pub', 'get') $Log 'flutter pub get failed' 13

    Step '[4/7] Requiring a clean analyzer result'
    Invoke-FlutterLogged $flutter @(
        'analyze',
        '--no-fatal-warnings',
        '--no-fatal-infos'
    ) $Log 'flutter analyze reported errors' 14

    if (-not $SkipTests) {
        Step '[5/7] Running Flutter tests'
        Invoke-FlutterLogged $flutter @('test', '--reporter', 'expanded') $Log 'flutter test failed' 15
    } else {
        Step '[5/7] Tests skipped by request' Yellow
    }

    Step '[6/7] Building Windows x64 release'
    Invoke-FlutterLogged $flutter @('config', '--enable-windows-desktop') $Log 'Could not enable Windows desktop support' 16
    Invoke-FlutterLogged $flutter @(
        'build',
        'windows',
        '--release',
        '--build-name',
        $BuildName,
        '--build-number',
        $BuildNumber.ToString()
    ) $Log 'Windows release build failed. Visual Studio 2022 with Desktop development with C++ may be required' 17

    if ($BuildAndroid) {
        Step '      Building optional Android APK'
        Invoke-FlutterLogged $flutter @(
            'build',
            'apk',
            '--release',
            '--build-name',
            $BuildName,
            '--build-number',
            $BuildNumber.ToString()
        ) $Log 'Android release build failed' 18
    }

    Step '[7/7] Packaging verified Windows release'
    $Release = Join-Path $WorkSource 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $Release -PathType Container)) {
        Stop-Build "Expected Windows release directory was not produced: $Release" 19
    }

    $expectedExe = Join-Path $Release 'neura_drive_rebuild.exe'
    if (Test-Path -LiteralPath $expectedExe -PathType Leaf) {
        $Exe = $expectedExe
    } else {
        $Exe = Get-ChildItem -LiteralPath $Release -Filter '*.exe' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        Stop-Build "Expected Windows executable was not produced under: $Release" 20
    }

    $builtUtc = (Get-Date).ToUniversalTime().ToString('o')
    @"
Neura Companion - Google Drive Rebuild
Version: $BuildName
Build number: $BuildNumber
Built: $builtUtc
Source mode: $sourceMode
Source: $SourceRoot
Pubspec package: $pubspecName

Install:
1. Extract the complete ZIP.
2. Keep the executable, DLLs, and data folder together.
3. Run $([IO.Path]::GetFileName($Exe)).

This package passed dependency restore, Flutter analysis, tests (unless
explicitly skipped), and Windows release compilation during this build.

This is a portable release ZIP, not an installer.
"@ | Set-Content -LiteralPath (Join-Path $Release 'README_INSTALL.txt') -Encoding UTF8

    $manifest = [ordered]@{
        schema_version = 1
        app = 'Neura Companion'
        build_name = $BuildName
        build_number = $BuildNumber
        built_utc = $builtUtc
        source_mode = $sourceMode
        source_root = $SourceRoot
        package_root = $PackageRoot
        pubspec_name = $pubspecName
        dart_file_count = $dartCount
        tests_skipped = [bool]$SkipTests
        android_requested = [bool]$BuildAndroid
        flutter_executable = $flutter
        windows_executable = [IO.Path]::GetFileName($Exe)
        staging_root = $WorkRoot
    }
    $manifest |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $Release 'BUILD_MANIFEST.json') -Encoding UTF8

    $Zip = Join-Path $Dist "NeuraCompanion_GoogleDriveRebuild_Windows_x64_$safeBuildName.zip"
    $ZipHashPath = Join-Path $Dist "NeuraCompanion_GoogleDriveRebuild_Windows_x64_${safeBuildName}_SHA256.txt"
    if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
    if (Test-Path -LiteralPath $ZipHashPath) { Remove-Item -LiteralPath $ZipHashPath -Force }

    Compress-Archive -Path (Join-Path $Release '*') -DestinationPath $Zip -CompressionLevel Optimal
    $Hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$Hash  $([IO.Path]::GetFileName($Zip))" |
        Set-Content -LiteralPath $ZipHashPath -Encoding ASCII

    if ($BuildAndroid) {
        $Apk = Join-Path $WorkSource 'build\app\outputs\flutter-apk\app-release.apk'
        if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) {
            Stop-Build "Android build succeeded but the release APK was not found: $Apk" 21
        }

        $ApkOut = Join-Path $Dist "NeuraCompanion_GoogleDriveRebuild_Android_$safeBuildName.apk"
        Copy-Item -LiteralPath $Apk -Destination $ApkOut -Force
        $ApkHash = (Get-FileHash -LiteralPath $ApkOut -Algorithm SHA256).Hash.ToLowerInvariant()
        "$ApkHash  $([IO.Path]::GetFileName($ApkOut))" |
            Set-Content -LiteralPath (Join-Path $Dist "NeuraCompanion_GoogleDriveRebuild_Android_${safeBuildName}_SHA256.txt") -Encoding ASCII
    }
} finally {
    Pop-Location
}

Step ''
Step 'Native Neura build completed.' Green
Step "  Windows ZIP : $Zip" Green
Step "  SHA-256     : $Hash"
if ($ApkOut) {
    Step "  Android APK: $ApkOut" Green
    Step "  APK SHA-256: $ApkHash"
}
Step "  Build log   : $Log"
Step "  Staging kept: $WorkRoot"
Step ''
exit 0
