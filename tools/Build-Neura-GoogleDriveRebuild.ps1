#Requires -Version 5.1
<#
.SYNOPSIS
Builds recovered Neura Flutter source from an isolated staging copy.

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
  4. Restore authored source and platform files.
  5. Run flutter pub get.
  6. Require flutter analyze to succeed.
  7. Run flutter test unless -SkipTests.
  8. Build Windows x64 release.
  9. Optionally build an Android APK.
 10. Package portable outputs and SHA-256 checksums under dist.
 11. Optionally compile a per-user Windows installer with Inno Setup.

This script does not merge historical forks, modify the original recovered
snapshot, prove end-user data recovery, or sign release artifacts.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 -Yes

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -PackageRoot "D:\NeuraRecovery" `
  -FlutterPath "C:\src\flutter\bin\flutter.bat" `
  -BuildAndroid `
  -BuildInstaller
#>
[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SourceRoot,
    [string]$FlutterPath,
    [string]$InnoSetupPath,
    [string]$BuildName = '1.1.0',
    [int]$BuildNumber = 2,
    [switch]$SkipTests,
    [switch]$BuildAndroid,
    [switch]$BuildInstaller,
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

function Resolve-InnoCompiler([string]$RequestedPath) {
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidate = [Environment]::ExpandEnvironmentVariables($RequestedPath)

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }

        $exeCandidate = Join-Path $candidate 'ISCC.exe'
        if (Test-Path -LiteralPath $exeCandidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $exeCandidate).Path
        }
    }

    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $common = New-Object System.Collections.Generic.List[string]
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $common.Add((Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $common.Add((Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'))
    }

    return ($common |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1)
}

function Copy-DirectoryContents([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From -PathType Container)) { return }

    New-Item -ItemType Directory -Path $To -Force | Out-Null
    Get-ChildItem -LiteralPath $From -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $To -Recurse -Force
    }
}

function Copy-RecoverySource([string]$From, [string]$To) {
    $excludedNames = @(
        '.git',
        '.dart_tool',
        '.neura_repair',
        '.pub',
        'build',
        'dist',
        '.idea',
        '.vs'
    )

    Get-ChildItem -LiteralPath $From -Force |
        Where-Object { $excludedNames -notcontains $_.Name } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $To -Recurse -Force
        }
}

function Invoke-LoggedProcess(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$LogPath,
    [string]$FailureMessage,
    [int]$FailureCode
) {
    & $Executable @Arguments *>&1 |
        Tee-Object -FilePath $LogPath -Append |
        Out-Host

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Stop-Build "$FailureMessage (exit code $exitCode)." $FailureCode
    }
}

function Restore-EnvironmentVariable([string]$Name, [string]$PreviousValue, [bool]$Existed) {
    if ($Existed) {
        [Environment]::SetEnvironmentVariable($Name, $PreviousValue, 'Process')
    } else {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
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
if ([string]::IsNullOrWhiteSpace($BuildName)) {
    Stop-Build 'BuildName cannot be empty.'
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

$InstallerTemplate = Join-Path $PSScriptRoot 'installer\NeuraCompanion.iss'
$inno = $null
if ($BuildInstaller) {
    if (-not (Test-Path -LiteralPath $InstallerTemplate -PathType Leaf)) {
        Stop-Build "Installer template is missing: $InstallerTemplate" 21
    }

    $inno = Resolve-InnoCompiler $InnoSetupPath
    if (-not $inno) {
        Stop-Build 'Inno Setup compiler (ISCC.exe) was not found. Install Inno Setup 6 or pass -InnoSetupPath.' 22
    }
}

$pubspecName = 'unknown'
$nameMatch = Select-String -LiteralPath (Join-Path $SourceRoot 'pubspec.yaml') -Pattern '^\s*name:\s*(.+?)\s*$' |
    Select-Object -First 1
if ($nameMatch) {
    $pubspecName = $nameMatch.Matches[0].Groups[1].Value.Trim()
}
$dartCount = @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'lib') -Recurse -File -Filter '*.dart').Count
$scaffoldProjectName = if ($pubspecName -match '^[a-z][a-z0-9_]*$') {
    $pubspecName
} else {
    'neura_drive_rebuild'
}

$Dist = Join-Path $PackageRoot 'dist'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$WorkRoot = Join-Path $env:LOCALAPPDATA "NeuraCompanion\Builds\DriveRebuild_$Stamp"
$WorkSource = Join-Path $WorkRoot 'source'
$Preserve = Join-Path $WorkRoot 'preserve'
New-Item -ItemType Directory -Path $WorkSource -Force | Out-Null
New-Item -ItemType Directory -Path $Preserve -Force | Out-Null
New-Item -ItemType Directory -Path $Dist -Force | Out-Null
$Log = Join-Path $Dist "DriveRebuild_build_$Stamp.log"
$ToolchainManifest = Join-Path $WorkRoot 'TOOLCHAIN_MANIFEST.txt'

Step ''
Step 'NEURA COMPANION - GOOGLE DRIVE REBUILD' Magenta
Step "  Package      : $PackageRoot"
Step "  Source       : $SourceRoot"
Step "  Source mode  : $sourceMode"
Step "  Pubspec name : $pubspecName"
Step "  Dart files   : $dartCount"
Step "  Staging      : $WorkSource"
Step "  Flutter      : $flutter"
if ($BuildInstaller) {
    Step "  Inno Setup   : $inno"
}
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

# Build from an isolated copy so recovered snapshots remain untouched.
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

# Preserve authored source and platform customizations because flutter create may
# regenerate template files while adding missing scaffolding.
foreach ($name in @('lib', 'test', 'assets', 'windows', 'android')) {
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
$ZipHashPath = $null
$ApkOut = $null
$ApkHash = $null
$InstallerOut = $null
$InstallerHash = $null
$InstallerHashPath = $null
$Release = $null
$Exe = $null
$safeBuildName = $BuildName -replace '[^0-9A-Za-z._-]', '_'
$platforms = if ($BuildAndroid) { 'windows,android' } else { 'windows' }

Push-Location $WorkSource
try {
    Step '[1/8] Recording Flutter and Windows toolchain'
    @"
Neura Companion build toolchain
Captured UTC: $((Get-Date).ToUniversalTime().ToString('o'))
PowerShell: $($PSVersionTable.PSVersion)
OS: $([Environment]::OSVersion.VersionString)
Flutter executable: $flutter
Source mode: $sourceMode
Source root: $SourceRoot
"@ | Set-Content -LiteralPath $ToolchainManifest -Encoding UTF8

    Invoke-LoggedProcess $flutter @('--version') $Log 'Flutter could not start' 11
    (& $flutter --version *>&1) | Add-Content -LiteralPath $ToolchainManifest -Encoding UTF8

    Step '      Recording flutter doctor -v (diagnostic; not a release gate)'
    $doctorOutput = @(& $flutter doctor -v *>&1)
    $doctorExit = $LASTEXITCODE
    $doctorOutput |
        Tee-Object -FilePath $Log -Append |
        Tee-Object -FilePath $ToolchainManifest -Append |
        Out-Host
    if ($doctorExit -ne 0) {
        Step "      [!] flutter doctor exited $doctorExit. Build gates below remain authoritative." Yellow
    }

    Step '[2/8] Creating missing platform scaffolds'
    Invoke-LoggedProcess $flutter @(
        'create',
        '.',
        '--project-name',
        $scaffoldProjectName,
        '--org',
        'com.vantiger.neura',
        '--platforms',
        $platforms
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

    foreach ($name in @('windows', 'android')) {
        $authored = Join-Path $Preserve $name
        $generated = Join-Path $WorkSource $name
        Copy-DirectoryContents $authored $generated
    }

    foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml', 'README.md')) {
        $authored = Join-Path $Preserve $name
        if (Test-Path -LiteralPath $authored -PathType Leaf) {
            Copy-Item -LiteralPath $authored -Destination (Join-Path $WorkSource $name) -Force
        }
    }

    Step '[3/8] Restoring dependencies'
    Invoke-LoggedProcess $flutter @('pub', 'get') $Log 'flutter pub get failed' 13

    Step '[4/8] Requiring a clean analyzer result'
    Invoke-LoggedProcess $flutter @(
        'analyze',
        '--no-fatal-warnings',
        '--no-fatal-infos'
    ) $Log 'flutter analyze reported errors' 14

    if (-not $SkipTests) {
        Step '[5/8] Running Flutter tests'
        Invoke-LoggedProcess $flutter @('test', '--reporter', 'expanded') $Log 'flutter test failed' 15
    } else {
        Step '[5/8] Tests skipped by request' Yellow
    }

    Step '[6/8] Building Windows x64 release'
    Invoke-LoggedProcess $flutter @('config', '--enable-windows-desktop') $Log 'Could not enable Windows desktop support' 16
    Invoke-LoggedProcess $flutter @(
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
        Invoke-LoggedProcess $flutter @(
            'build',
            'apk',
            '--release',
            '--build-name',
            $BuildName,
            '--build-number',
            $BuildNumber.ToString()
        ) $Log 'Android release build failed' 18
    }

    Step '[7/8] Packaging verified portable release'
    $Release = Join-Path $WorkSource 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $Release -PathType Container)) {
        Stop-Build "Expected Windows release directory was not produced: $Release" 19
    }

    $expectedExeNames = @(
        "$scaffoldProjectName.exe",
        'neuro_companion.exe',
        'neura_drive_rebuild.exe'
    ) | Select-Object -Unique

    foreach ($expectedExeName in $expectedExeNames) {
        $candidateExe = Join-Path $Release $expectedExeName
        if (Test-Path -LiteralPath $candidateExe -PathType Leaf) {
            $Exe = $candidateExe
            break
        }
    }
    if (-not $Exe) {
        $Exe = Get-ChildItem -LiteralPath $Release -Filter '*.exe' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        Stop-Build "Expected Windows executable was not produced under: $Release" 20
    }

    Copy-Item -LiteralPath $ToolchainManifest -Destination (Join-Path $Release 'TOOLCHAIN_MANIFEST.txt') -Force

    $builtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $installReadme = @"
Neura Companion - Google Drive Rebuild
Version: $BuildName
Build number: $BuildNumber
Built: $builtUtc
Source mode: $sourceMode
Source: $SourceRoot
Pubspec package: $pubspecName

Portable ZIP:
1. Extract the complete ZIP.
2. Keep the executable, DLLs, and data folder together.
3. Run $([IO.Path]::GetFileName($Exe)).

Installer:
When the build was run with -BuildInstaller, use the matching
NeuraCompanion_Setup_$safeBuildName.exe from the dist folder.

This package passed dependency restore, Flutter analysis, tests (unless
explicitly skipped), and Windows release compilation during this build.

The installer is unsigned unless it is signed separately after compilation.
"@
    $installReadme |
        Set-Content -LiteralPath (Join-Path $Release 'README_INSTALL.txt') -Encoding UTF8

    $manifest = [ordered]@{
        schema_version = 2
        app = 'Neura Companion'
        build_name = $BuildName
        build_number = $BuildNumber
        built_utc = $builtUtc
        source_mode = $sourceMode
        source_root = $SourceRoot
        package_root = $PackageRoot
        pubspec_name = $pubspecName
        scaffold_project_name = $scaffoldProjectName
        dart_file_count = $dartCount
        tests_skipped = [bool]$SkipTests
        android_requested = [bool]$BuildAndroid
        installer_requested = [bool]$BuildInstaller
        flutter_executable = $flutter
        inno_setup_compiler = $inno
        windows_executable = [IO.Path]::GetFileName($Exe)
        staging_root = $WorkRoot
        build_log = $Log
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
            Stop-Build "Android build succeeded but the release APK was not found: $Apk" 23
        }

        $ApkOut = Join-Path $Dist "NeuraCompanion_GoogleDriveRebuild_Android_$safeBuildName.apk"
        Copy-Item -LiteralPath $Apk -Destination $ApkOut -Force
        $ApkHash = (Get-FileHash -LiteralPath $ApkOut -Algorithm SHA256).Hash.ToLowerInvariant()
        "$ApkHash  $([IO.Path]::GetFileName($ApkOut))" |
            Set-Content -LiteralPath (Join-Path $Dist "NeuraCompanion_GoogleDriveRebuild_Android_${safeBuildName}_SHA256.txt") -Encoding ASCII
    }

    if ($BuildInstaller) {
        Step '[8/8] Compiling Neura Companion Windows installer'

        $environmentNames = @(
            'NEURA_INSTALLER_SOURCE',
            'NEURA_INSTALLER_OUTPUT',
            'NEURA_INSTALLER_VERSION',
            'NEURA_INSTALLER_SAFE_VERSION',
            'NEURA_INSTALLER_EXE'
        )
        $previousEnvironment = @{}
        foreach ($name in $environmentNames) {
            $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            $previousEnvironment[$name] = [ordered]@{
                existed = ($null -ne $item)
                value = if ($item) { [string]$item.Value } else { $null }
            }
        }

        try {
            $env:NEURA_INSTALLER_SOURCE = $Release
            $env:NEURA_INSTALLER_OUTPUT = $Dist
            $env:NEURA_INSTALLER_VERSION = $BuildName
            $env:NEURA_INSTALLER_SAFE_VERSION = $safeBuildName
            $env:NEURA_INSTALLER_EXE = [IO.Path]::GetFileName($Exe)

            Invoke-LoggedProcess $inno @($InstallerTemplate) $Log 'Inno Setup installer compilation failed' 24
        } finally {
            foreach ($name in $environmentNames) {
                $entry = $previousEnvironment[$name]
                Restore-EnvironmentVariable $name ([string]$entry.value) ([bool]$entry.existed)
            }
        }

        $InstallerOut = Join-Path $Dist "NeuraCompanion_Setup_$safeBuildName.exe"
        if (-not (Test-Path -LiteralPath $InstallerOut -PathType Leaf)) {
            Stop-Build "Inno Setup completed but the expected installer was not found: $InstallerOut" 25
        }

        $InstallerHash = (Get-FileHash -LiteralPath $InstallerOut -Algorithm SHA256).Hash.ToLowerInvariant()
        $InstallerHashPath = Join-Path $Dist "NeuraCompanion_Setup_${safeBuildName}_SHA256.txt"
        "$InstallerHash  $([IO.Path]::GetFileName($InstallerOut))" |
            Set-Content -LiteralPath $InstallerHashPath -Encoding ASCII
    } else {
        Step '[8/8] Installer not requested; portable ZIP is complete' DarkGray
    }
} finally {
    Pop-Location
}

Step ''
Step 'Native Neura build completed.' Green
Step "  Windows ZIP : $Zip" Green
Step "  ZIP SHA-256 : $Hash"
if ($InstallerOut) {
    Step "  Installer   : $InstallerOut" Green
    Step "  EXE SHA-256 : $InstallerHash"
    Step '  Signing     : unsigned; sign before public distribution' Yellow
}
if ($ApkOut) {
    Step "  Android APK : $ApkOut" Green
    Step "  APK SHA-256 : $ApkHash"
}
Step "  Build log   : $Log"
Step "  Toolchain   : $ToolchainManifest"
Step "  Staging kept: $WorkRoot"
Step ''
exit 0
