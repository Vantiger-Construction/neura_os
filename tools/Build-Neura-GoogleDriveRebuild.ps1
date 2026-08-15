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
  3. Reuse valid platform scaffolds; generate only missing Windows/Android
     scaffolds.
  4. Restore authored source/platform files and verify the native bootstrap
     contract.
  5. Run flutter pub get.
  6. Require flutter analyze to succeed.
  7. Run flutter test unless -SkipTests.
  8. Build Windows x64 release.
  9. Optionally build an Android APK.
 10. Verify the runtime payload and package app-local Visual C++ dependencies.
 11. Package portable outputs and SHA-256 checksums under dist.
 12. Optionally compile a per-user Windows installer with Inno Setup.

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
    [string]$BuildName,
    [int]$BuildNumber = 0,
    [switch]$SkipTests,
    [switch]$SkipLaunchSmokeTest,
    [switch]$BuildAndroid,
    [switch]$BuildInstaller,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$LaunchSmokeSuccessExitCode = 73

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
        $common.Add((Join-Path $programFilesX86 'Inno Setup 7\ISCC.exe'))
        $common.Add((Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $common.Add((Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'))
        $common.Add((Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'))
    }

    return ($common |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1)
}

function Test-FlutterPlatformScaffold([string]$Root, [string]$Platform) {
    switch ($Platform) {
        'windows' {
            return (
                (Test-Path -LiteralPath (Join-Path $Root 'windows\CMakeLists.txt') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $Root 'windows\runner\CMakeLists.txt') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $Root 'windows\runner\main.cpp') -PathType Leaf)
            )
        }
        'android' {
            $settingsPresent = (
                (Test-Path -LiteralPath (Join-Path $Root 'android\settings.gradle') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path $Root 'android\settings.gradle.kts') -PathType Leaf)
            )
            $appBuildPresent = (
                (Test-Path -LiteralPath (Join-Path $Root 'android\app\build.gradle') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path $Root 'android\app\build.gradle.kts') -PathType Leaf)
            )
            return (
                $settingsPresent -and
                $appBuildPresent -and
                (Test-Path -LiteralPath (Join-Path $Root 'android\app\src\main\AndroidManifest.xml') -PathType Leaf)
            )
        }
        default { return $false }
    }
}

function Assert-NeuraWindowsBootstrapContract([string]$Root) {
    $dartMainPath = Join-Path $Root 'lib\main.dart'
    $dartMain = Get-Content -LiteralPath $dartMainPath -Raw
    if ($dartMain -notmatch 'NeuraWindowRole') { return }

    $requiredFiles = @(
        'windows\runner\neura_window_role.h',
        'windows\runner\neura_window_role.cpp',
        'windows\runner\main.cpp',
        'windows\runner\CMakeLists.txt'
    )
    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
            Stop-Build "The Dart entrypoint uses NeuraWindowRole, but authored Windows bootstrap file is missing: $relativePath" 26
        }
    }

    $roleSource = Get-Content -LiteralPath (Join-Path $Root 'windows\runner\neura_window_role.cpp') -Raw
    $runnerMain = Get-Content -LiteralPath (Join-Path $Root 'windows\runner\main.cpp') -Raw
    $runnerCmake = Get-Content -LiteralPath (Join-Path $Root 'windows\runner\CMakeLists.txt') -Raw
    if ($roleSource -notmatch 'neura/window_role') {
        Stop-Build 'The Windows role source does not register the neura/window_role channel.' 26
    }
    if ($runnerCmake -notmatch 'neura_window_role\.cpp') {
        Stop-Build 'windows/runner/CMakeLists.txt does not compile neura_window_role.cpp.' 26
    }
    if ($runnerMain -notmatch 'WindowManagerPlusPluginSetWindowCreatedCallback') {
        Stop-Build 'The authored Windows runner is missing Neura secondary-window creation wiring.' 26
    }
}

function Assert-NeuraWindowsBuildTools([string]$Root) {
    $runnerCmakePath = Join-Path $Root 'windows\runner\CMakeLists.txt'
    if (-not (Test-Path -LiteralPath $runnerCmakePath -PathType Leaf)) { return }
    $runnerCmake = Get-Content -LiteralPath $runnerCmakePath -Raw

    if (($runnerCmake -match 'find_program\(CARGO_EXE') -and
        -not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Stop-Build 'The authored Windows runner builds neura_swarm, but cargo is not available on PATH.' 27
    }
    if (($runnerCmake -match 'find_program\(NUGET_EXE') -and
        -not (Get-Command nuget.exe -ErrorAction SilentlyContinue) -and
        -not (Get-Command nuget -ErrorAction SilentlyContinue)) {
        Stop-Build 'The authored Windows runner requires nuget.exe, but NuGet is not available on PATH.' 27
    }
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
        $patterns = @(
            (Join-Path $programRoot "Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT\$Name"),
            (Join-Path $programRoot "Microsoft Visual Studio\2019\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT\$Name")
        )
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
                ForEach-Object { $runtimeFiles.Add($_) }
        }
    }
    $redistMatch = $runtimeFiles | Sort-Object -Property FullName -Descending | Select-Object -First 1
    if ($redistMatch) { return $redistMatch.FullName }
    return $null
}

function Assert-WindowsRuntimePayload(
    [string]$ReleaseRoot,
    [string]$ExecutablePath,
    [bool]$RequireSwarmDll
) {
    $criticalFiles = @(
        $ExecutablePath,
        (Join-Path $ReleaseRoot 'flutter_windows.dll'),
        (Join-Path $ReleaseRoot 'data\icudtl.dat'),
        (Join-Path $ReleaseRoot 'data\app.so'),
        (Join-Path $ReleaseRoot 'data\flutter_assets\AssetManifest.bin')
    )
    if ($RequireSwarmDll) {
        $criticalFiles += (Join-Path $ReleaseRoot 'neura_swarm.dll')
    }

    foreach ($criticalFile in $criticalFiles) {
        if (-not (Test-Path -LiteralPath $criticalFile -PathType Leaf)) {
            Stop-Build "Windows runtime payload is incomplete; missing: $criticalFile" 28
        }
        if ((Get-Item -LiteralPath $criticalFile).Length -le 0) {
            Stop-Build "Windows runtime payload contains an empty file: $criticalFile" 28
        }
    }

    # Flutter Windows binaries use the MSVC runtime. Ship the x64 CRT app-local
    # so the portable ZIP and per-user installer do not open and immediately
    # close on a clean machine that lacks the system-wide redistributable.
    $vcRuntimeNames = @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )
    foreach ($runtimeName in $vcRuntimeNames) {
        $destination = Join-Path $ReleaseRoot $runtimeName
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            $source = Find-VcRuntimeFile $runtimeName
            if (-not $source) {
                Stop-Build "Required Visual C++ redistributable file was not found in a Visual Studio VC Redist x64 directory: $runtimeName. Install the Desktop development with C++ workload and its redistributable components." 28
            }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        if ((Get-Item -LiteralPath $destination).Length -le 0) {
            Stop-Build "Packaged Visual C++ runtime is empty: $destination" 28
        }
    }

    # Newer MSVC toolsets split a few C++ facilities into companion DLLs.
    # Copy them when available; older toolsets legitimately do not ship all
    # of these, so only the core three above are mandatory.
    foreach ($runtimeName in @(
        'concrt140.dll',
        'msvcp140_atomic_wait.dll',
        'msvcp140_codecvt_ids.dll',
        'vcomp140.dll'
    )) {
        $destination = Join-Path $ReleaseRoot $runtimeName
        if (Test-Path -LiteralPath $destination -PathType Leaf) { continue }
        $source = Find-VcRuntimeFile $runtimeName
        if ($source) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }

    $emptyDll = Get-ChildItem -LiteralPath $ReleaseRoot -Filter '*.dll' -File -Recurse |
        Where-Object { $_.Length -le 0 } |
        Select-Object -First 1
    if ($emptyDll) {
        Stop-Build "Windows runtime payload contains an empty DLL: $($emptyDll.FullName)" 28
    }
}

function Invoke-WindowsLaunchSmokeTest(
    [string]$ExecutablePath,
    [int]$TimeoutSeconds = 15
) {
    $process = $null
    $smokePid = $null
    $result = $null
    $cleanupFailure = $null
    $startedAt = [DateTime]::UtcNow
    try {
        if ($TimeoutSeconds -lt 1) {
            throw 'Launch smoke-test timeout must be at least one second.'
        }

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $ExecutablePath
        $startInfo.Arguments = '--launch-smoke-test'
        $startInfo.WorkingDirectory = Split-Path -Parent $ExecutablePath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $false

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            $result = [pscustomobject]@{
                passed = $false
                detail = 'Windows did not start the packaged executable.'
                pid = $null
            }
        } else {
            $smokePid = $process.Id
            $completed = $process.WaitForExit($TimeoutSeconds * 1000)
            $elapsedSeconds =
                [Math]::Round(([DateTime]::UtcNow - $startedAt).TotalSeconds, 2)
            if ($completed) {
                $exitCode = $process.ExitCode
                $passed = ($exitCode -eq $LaunchSmokeSuccessExitCode)
                $detail =
                    "Launch self-test exited with code $exitCode (expected sentinel $LaunchSmokeSuccessExitCode) after $elapsedSeconds second(s)."
                $result = [pscustomobject]@{
                    passed = $passed
                    detail = $detail
                    pid = $smokePid
                }
            } else {
                $result = [pscustomobject]@{
                    passed = $false
                    detail = "Launch self-test did not self-exit within $TimeoutSeconds second(s)."
                    pid = $smokePid
                }
            }
        }
    } catch {
        $result = [pscustomobject]@{
            passed = $false
            detail = "Launch smoke test failed: $($_.Exception.Message)"
            pid = $smokePid
        }
    } finally {
        if ($process -and $null -ne $smokePid) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) {
                    # A conforming launch self-test exits by itself. Reaching
                    # this branch means it timed out or startup threw. Stop
                    # only the exact PID created above; never name-match or
                    # terminate a normal, passing application instance.
                    Stop-Process -Id $smokePid -Force -ErrorAction Stop
                    $process.WaitForExit(5000) | Out-Null
                }
            } catch {
                $cleanupFailure =
                    "Could not stop timed-out smoke-test PID ${smokePid}: $($_.Exception.Message)"
            }
        }
        if ($process) { $process.Dispose() }
    }

    if ($cleanupFailure) {
        return [pscustomobject]@{
            passed = $false
            detail = $cleanupFailure
            pid = $smokePid
        }
    }
    return $result
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

$pubspecVersionMatch = Select-String `
    -LiteralPath (Join-Path $SourceRoot 'pubspec.yaml') `
    -Pattern '^\s*version:\s*([^+\s#]+)(?:\+([0-9]+))?\s*(?:#.*)?$' |
    Select-Object -First 1
if (-not $pubspecVersionMatch) {
    Stop-Build 'pubspec.yaml must declare a version (for example, version: 1.3.0+5).'
}
$pubspecBuildName = $pubspecVersionMatch.Matches[0].Groups[1].Value
$pubspecBuildNumberText = $pubspecVersionMatch.Matches[0].Groups[2].Value
if ([string]::IsNullOrWhiteSpace($BuildName)) {
    $BuildName = $pubspecBuildName
}
if ($BuildName -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') {
    Stop-Build "BuildName must be a semantic version such as 1.3.0: $BuildName"
}
if ($BuildNumber -eq 0) {
    $BuildNumber = if ([string]::IsNullOrWhiteSpace($pubspecBuildNumberText)) {
        1
    } else {
        [int]$pubspecBuildNumberText
    }
}
if ($BuildNumber -lt 1) {
    Stop-Build 'BuildNumber must be 1 or greater.'
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
        Stop-Build 'Inno Setup compiler (ISCC.exe) was not found. Install Inno Setup 6.3 or newer, or pass -InnoSetupPath.' 22
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
Step "  Version      : $BuildName+$BuildNumber"
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

$requestedPlatforms = @('windows')
if ($BuildAndroid) { $requestedPlatforms += 'android' }

# Preserve authored source and only the platform trees requested for this build.
# If a missing scaffold must be generated, these exact trees are restored after
# flutter create so custom native channels and CMake wiring cannot be replaced.
foreach ($name in @('lib', 'test', 'assets')) {
    $sourceDirectory = Join-Path $WorkSource $name
    if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
        Copy-Item -LiteralPath $sourceDirectory -Destination (Join-Path $Preserve $name) -Recurse -Force
    }
}
foreach ($name in $requestedPlatforms) {
    $platformDirectory = Join-Path $WorkSource $name
    if (Test-Path -LiteralPath $platformDirectory -PathType Container) {
        Copy-Item -LiteralPath $platformDirectory -Destination (Join-Path $Preserve $name) -Recurse -Force
    }
}
foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml', 'README.md')) {
    $sourceFile = Join-Path $WorkSource $name
    if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $Preserve $name) -Force
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
$launchSmokeStatus = 'not_run'
$launchSmokeDetail = ''
$safeBuildName = $BuildName -replace '[^0-9A-Za-z._-]', '_'
$missingPlatforms = @(
    $requestedPlatforms |
        Where-Object { -not (Test-FlutterPlatformScaffold $WorkSource $_) }
)

Push-Location $WorkSource
try {
    Step '[1/9] Recording Flutter and Windows toolchain'
    @"
Neura Companion build toolchain
Captured UTC: $((Get-Date).ToUniversalTime().ToString('o'))
PowerShell: $($PSVersionTable.PSVersion)
OS: $([Environment]::OSVersion.VersionString)
Flutter executable: $flutter
Source mode: $sourceMode
Source root: $SourceRoot
"@ | Set-Content -LiteralPath $ToolchainManifest -Encoding UTF8

    $flutterVersionOutput = @(& $flutter --version *>&1)
    $flutterVersionExit = $LASTEXITCODE
    $flutterVersionOutput |
        Tee-Object -FilePath $Log -Append |
        Tee-Object -FilePath $ToolchainManifest -Append |
        Out-Host
    if ($flutterVersionExit -ne 0) {
        Stop-Build "Flutter could not start (exit code $flutterVersionExit)." 11
    }

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

    if ($missingPlatforms.Count -gt 0) {
        $platformList = $missingPlatforms -join ','
        Step "[2/9] Creating missing platform scaffolds only: $platformList"
        Invoke-LoggedProcess $flutter @(
            'create',
            '.',
            '--project-name',
            $scaffoldProjectName,
            '--org',
            'com.vantiger.neura',
            '--platforms',
            $platformList
        ) $Log 'flutter create failed' 12
    } else {
        Step '[2/9] Platform scaffolds are complete; skipping flutter create' DarkGray
    }

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

    foreach ($name in $requestedPlatforms) {
        $authored = Join-Path $Preserve $name
        $generated = Join-Path $WorkSource $name
        if (Test-Path -LiteralPath $authored -PathType Container) {
            if ($missingPlatforms -contains $name) {
                # The authored tree was incomplete, so keep newly generated
                # missing files while restoring every recovered customization.
                New-Item -ItemType Directory -Path $generated -Force | Out-Null
                Get-ChildItem -LiteralPath $authored -Force | ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $generated -Recurse -Force
                }
            } else {
                # A valid authored platform is source-of-truth; restore it
                # byte-for-byte instead of retaining template rewrites.
                if (Test-Path -LiteralPath $generated) {
                    Remove-Item -LiteralPath $generated -Recurse -Force
                }
                Copy-Item -LiteralPath $authored -Destination $generated -Recurse -Force
            }
        }
    }

    foreach ($name in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'l10n.yaml', 'README.md')) {
        $authored = Join-Path $Preserve $name
        if (Test-Path -LiteralPath $authored -PathType Leaf) {
            Copy-Item -LiteralPath $authored -Destination (Join-Path $WorkSource $name) -Force
        }
    }

    Assert-NeuraWindowsBootstrapContract $WorkSource
    Assert-NeuraWindowsBuildTools $WorkSource

    Step '[3/9] Restoring dependencies'
    Invoke-LoggedProcess $flutter @('pub', 'get') $Log 'flutter pub get failed' 13

    Step '[4/9] Requiring a clean analyzer result'
    Invoke-LoggedProcess $flutter @(
        'analyze',
        '--no-fatal-warnings',
        '--no-fatal-infos'
    ) $Log 'flutter analyze reported errors' 14

    if (-not $SkipTests) {
        Step '[5/9] Running Flutter tests'
        Invoke-LoggedProcess $flutter @('test', '--reporter', 'expanded') $Log 'flutter test failed' 15
    } else {
        Step '[5/9] Tests skipped by request' Yellow
    }

    Step '[6/9] Building Windows x64 release'
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

    Step '[7/9] Validating Windows runtime payload'
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

    $runnerCmakeText = Get-Content -LiteralPath (Join-Path $WorkSource 'windows\runner\CMakeLists.txt') -Raw
    $requireSwarmDll = (
        (Test-Path -LiteralPath (Join-Path $WorkSource 'rust\Cargo.toml') -PathType Leaf) -and
        ($runnerCmakeText -match 'neura_swarm\.dll')
    )
    Assert-WindowsRuntimePayload $Release $Exe $requireSwarmDll

    if ($SkipLaunchSmokeTest) {
        $launchSmokeStatus = 'skipped'
        $launchSmokeDetail = 'Skipped explicitly with -SkipLaunchSmokeTest.'
        Step '      Launch smoke test skipped explicitly' Yellow
    } else {
        $smokeResult = Invoke-WindowsLaunchSmokeTest $Exe 15
        $launchSmokeDetail = [string]$smokeResult.detail
        if (-not [bool]$smokeResult.passed) {
            $launchSmokeStatus = 'failed'
            Stop-Build "Packaged executable failed the launch self-test. $launchSmokeDetail Logs: %TEMP%\neura_error_vault.jsonl; %LOCALAPPDATA%\Neura OS\Logs\bootstrap_crash.ndjson; %APPDATA%\com.neurocompanion\neuro_companion\neura\logs\neura.log.ndjson." 29
        }
        $launchSmokeStatus = 'passed'
        Step "      [OK] Launch smoke test: $launchSmokeDetail" Green
    }

    Step '[8/9] Packaging verified portable release'

    $builtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $flutterVersionLine = [string](
        $flutterVersionOutput | Select-Object -First 1
    )
    @"
Neura Companion packaged toolchain summary
Captured UTC: $builtUtc
PowerShell: $($PSVersionTable.PSVersion)
OS: $([Environment]::OSVersion.VersionString)
Flutter: $flutterVersionLine
Source mode: $sourceMode
Analysis: passed
Tests: $(if ($SkipTests) { 'skipped by request' } else { 'passed' })
Windows release build: passed
Runtime payload: passed
Launch smoke test: $launchSmokeStatus - $launchSmokeDetail

Full local tool paths and flutter doctor output are intentionally excluded.
"@ | Set-Content -LiteralPath (
        Join-Path $Release 'TOOLCHAIN_MANIFEST.txt'
    ) -Encoding UTF8

    $installReadme = @"
Neura Companion - Google Drive Rebuild
Version: $BuildName
Build number: $BuildNumber
Built: $builtUtc
Source mode: $sourceMode
Pubspec package: $pubspecName
Launch smoke test: $launchSmokeStatus - $launchSmokeDetail

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

Crash recovery logs:
- Native Windows vault: %TEMP%\neura_error_vault.jsonl
  (rotated copies: neura_error_vault.jsonl.1 through .3)
- Early/bootstrap: %LOCALAPPDATA%\Neura OS\Logs\bootstrap_crash.ndjson
  (rotated copy: bootstrap_crash.ndjson.old)
- App log: %APPDATA%\com.neurocompanion\neuro_companion\neura\logs\neura.log.ndjson
  (rotated copies: neura.log.ndjson.1 and neura.log.ndjson.2)
"@
    $installReadme |
        Set-Content -LiteralPath (Join-Path $Release 'README_INSTALL.txt') -Encoding UTF8

    $manifest = [ordered]@{
        schema_version = 3
        app = 'Neura Companion'
        build_name = $BuildName
        build_number = $BuildNumber
        built_utc = $builtUtc
        source_mode = $sourceMode
        pubspec_name = $pubspecName
        scaffold_project_name = $scaffoldProjectName
        dart_file_count = $dartCount
        tests_skipped = [bool]$SkipTests
        android_requested = [bool]$BuildAndroid
        installer_requested = [bool]$BuildInstaller
        generated_platform_scaffolds = @($missingPlatforms)
        windows_bootstrap_contract_verified = $true
        windows_runtime_payload_verified = $true
        launch_smoke_test_status = $launchSmokeStatus
        launch_smoke_test_detail = $launchSmokeDetail
        visual_cpp_runtime_packaged_app_local = $true
        native_swarm_dll_required = [bool]$requireSwarmDll
        windows_executable = [IO.Path]::GetFileName($Exe)
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
        Step '[9/9] Compiling Neura Companion Windows installer'

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
        Step '[9/9] Installer not requested; portable ZIP is complete' DarkGray
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
