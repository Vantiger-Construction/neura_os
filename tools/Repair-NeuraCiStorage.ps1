#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ToolCache = $env:RUNNER_TOOL_CACHE,
    [string]$RunnerTemp = $env:RUNNER_TEMP,
    [switch]$ClearValidationOutput,
    [string]$ValidationRunRoot,
    [switch]$ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NeuraOrdinaryDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and $item.PSIsContainer -and
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
}

function Remove-NeuraDerivedTree {
    param([Parameter(Mandatory)][string]$Path)
    # Avoid invoking the PowerShell provider for every SDK/cache file. A
    # large abandoned extraction can otherwise exceed the recovery timeout.
    # Enumerate one directory at a time and never use recursive deletion:
    # every entry is checked for reparse points, including nested links.
    $pending = New-Object System.Collections.Stack
    $directories = New-Object System.Collections.Stack
    $pending.Push($Path)
    while ($pending.Count -gt 0) {
        $current = [string]$pending.Pop()
        try {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Warning "Keeping linked cache entry: $current"
                continue
            }
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $children = [IO.Directory]::GetFileSystemEntries($current)
                $directories.Push($current)
                foreach ($child in $children) { $pending.Push($child) }
            } else {
                if (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                    [IO.File]::SetAttributes($current,
                        ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
                }
                [IO.File]::Delete($current)
            }
        } catch [IO.FileNotFoundException] {
            continue
        } catch [IO.DirectoryNotFoundException] {
            continue
        } catch {
            Write-Warning "Keeping unavailable cache entry ${current}: $($_.Exception.Message)"
        }
    }
    while ($directories.Count -gt 0) {
        $current = [string]$directories.Pop()
        try {
            $attributes = [IO.File]::GetAttributes($current)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if (($attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
                [IO.File]::SetAttributes($current,
                    ($attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
            }
            # Non-recursive deletion preserves any skipped or locked child.
            [IO.Directory]::Delete($current, $false)
        } catch [IO.DirectoryNotFoundException] {
            continue
        } catch {
            Write-Warning "Keeping nonempty or unavailable cache directory ${current}: $($_.Exception.Message)"
        }
    }
}

function Get-NeuraDirectoryBytes {
    param([Parameter(Mandatory)][string]$Path)
    [long]$bytes = 0
    if (-not (Test-NeuraOrdinaryDirectory -Path $Path)) { return $bytes }
    $pending = New-Object System.Collections.Stack
    $pending.Push($Path)
    while ($pending.Count -gt 0) {
        try { $entries = [IO.DirectoryInfo]::new([string]$pending.Pop()).GetFileSystemInfos() }
        catch { continue }
        foreach ($item in $entries) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if (($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0) { $pending.Push($item.FullName) }
            else { $bytes += $item.Length }
        }
    }
    return $bytes
}

function Test-NeuraUnlinkedPath {
    param([Parameter(Mandatory)][string]$Path)
    # Checking only the final directory would still follow a linked parent.
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if (-not $item -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $parent = [IO.Directory]::GetParent($current)
        $current = if ($parent) { $parent.FullName } else { $null }
    }
    return $true
}

function Clear-NeuraValidationOutput {
    param(
        [string]$RunRoot,
        [string]$RunKey,
        [switch]$ReportOnly
    )
    # Only the finishing job's generated output is eligible. Keep its checkout
    # and logs for actions/checkout's post step and never touch shared caches.
    if ([string]::IsNullOrWhiteSpace($RunRoot) -or $RunKey -notmatch '^\d+-\d+$') {
        Write-Host 'No current validation workspace was selected; nothing to release.'
        return
    }
    $root = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($RunRoot))
    if ($root.Name -notin @('state-matrix', 'living-intelligence', 'workspace') -or
        -not $root.Parent -or $root.Parent.Name -ne $RunKey -or
        -not $root.Parent.Parent -or $root.Parent.Parent.Name -ne 'neura-ci' -or
        -not (Test-NeuraUnlinkedPath -Path $root.FullName)) {
        Write-Warning 'Validation cleanup rejected a foreign or linked workspace.'
        return
    }
    $volume = [IO.Path]::GetPathRoot($root.FullName)
    $before = ([IO.DriveInfo]::new($volume)).AvailableFreeSpace
    # Windows release validation checks out directly into <run>/workspace.
    # Release its generated files now; retaining the Git checkout for its post
    # step must not also retain compiled Dart/Flutter data until aged recovery.
    $generated = if ($root.Name -eq 'workspace') {
        @('build', '.dart_tool', 'android/.gradle', 'rust/target',
            '.packages', 'windows/flutter/ephemeral')
    } else {
        @('workspace/build', 'workspace/.dart_tool', 'workspace/android/.gradle',
            'workspace/rust/target', 'workspace/.packages', 'temp')
    }
    foreach ($relative in $generated) {
        $path = Join-Path $root.FullName $relative
        if (-not (Test-NeuraUnlinkedPath -Path $path)) { continue }
        Write-Host "Completed validation output: $path (report-only=$([bool]$ReportOnly))"
        if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $path }
    }
    $after = ([IO.DriveInfo]::new($volume)).AvailableFreeSpace
    Write-Host ("Validation cleanup volume {0}: before={1:N2} GB; after={2:N2} GB; reclaimed={3:N2} GB" -f
        $volume, ($before / 1GB), ($after / 1GB),
        ([Math]::Max([long]0, [long]($after - $before)) / 1GB))
}

function Remove-NeuraAgedEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][datetime]$Before,
        [switch]$ReportOnly
    )
    if (-not (Test-NeuraUnlinkedPath -Path $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LastWriteTime -ge $Before) { return }
    $bytes = if ($item.PSIsContainer) { Get-NeuraDirectoryBytes -Path $Path } else { $item.Length }
    Write-Host ("Aged CI-generated entry: {0} ({1:N2} GB; report-only={2})" -f
        $Path, ($bytes / 1GB), [bool]$ReportOnly)
    if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $Path }
}

function Invoke-NeuraRunnerRecovery {
    param(
        [string]$RunnerTemp,
        [switch]$ReportOnly
    )
    if ([string]::IsNullOrWhiteSpace($RunnerTemp)) { return }
    $runnerWork = Split-Path -Parent $RunnerTemp
    if ((Split-Path -Leaf $RunnerTemp) -ne '_temp' -or
        (Split-Path -Leaf $runnerWork) -ne '_work' -or
        -not (Test-NeuraUnlinkedPath -Path $RunnerTemp)) {
        Write-Warning 'Runner temp layout is absent, unexpected, or linked; leaving it untouched.'
        return
    }
    # A job has one Runner.Worker. Do not reclaim shared data if another job
    # or a build/test process could still be using it. Age alone is insufficient.
    if (@(Get-Process -Name 'Runner.Worker' -ErrorAction SilentlyContinue).Count -gt 1 -or
        @(Get-Process -Name java, javaw, dart, flutter_tester, MSBuild, cl, rustc, cargo -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Host 'Keeping aged runner data while another worker or build process is active.'
        return
    }
    $cutoff = (Get-Date).AddHours(-2)
    $checkout = Join-Path (Join-Path $runnerWork 'neura_os') 'neura_os'
    foreach ($root in @($checkout, (Join-Path $checkout 'source'))) {
        foreach ($relative in @('build', 'rust/target', '.dart_tool', 'android/.gradle')) {
            Remove-NeuraAgedEntry -Path (Join-Path $root $relative) -Before $cutoff -ReportOnly:$ReportOnly
        }
    }
    # Folders first: a long backlog of tiny step scripts must not prevent
    # recovery of old extraction/test directories. Keep the 24-entry bound.
    Get-ChildItem -LiteralPath $RunnerTemp -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Sort-Object @{ Expression = 'PSIsContainer'; Descending = $true }, LastWriteTime |
        Select-Object -First 24 |
        ForEach-Object {
            Remove-NeuraAgedEntry -Path $_.FullName -Before $cutoff -ReportOnly:$ReportOnly
        }
    $diagnostics = Join-Path (Split-Path -Parent $runnerWork) '_diag'
    if (Test-NeuraUnlinkedPath -Path $diagnostics) {
        Get-ChildItem -LiteralPath $diagnostics -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^(Runner|Worker)_.*\.log$' -and
                $_.LastWriteTime -lt (Get-Date).AddDays(-7)
            } |
            Sort-Object LastWriteTime |
            Select-Object -First 24 |
            ForEach-Object {
                Remove-NeuraAgedEntry -Path $_.FullName -Before (Get-Date).AddDays(-7) -ReportOnly:$ReportOnly
            }
    }
}

function Remove-NeuraStalePackageRuns {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$RetainPerPlatform = 0,
        [int]$MaximumRemovals = 24,
        [switch]$ReportOnly
    )
    if (-not (Test-NeuraOrdinaryDirectory -Path $Root)) { return }
    $currentRun = if ($env:GITHUB_RUN_ID -and $env:GITHUB_RUN_ATTEMPT) {
        "$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
    } else { $null }
    $cutoff = (Get-Date).AddHours(-2)
    [int]$removed = 0
    foreach ($platform in @('android', 'windows')) {
        $platformRoot = Join-Path $Root $platform
        if (-not (Test-NeuraOrdinaryDirectory -Path $platformRoot)) { continue }
        $runs = @(
            Get-ChildItem -LiteralPath $platformRoot -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match '^\d+-\d+$' -and
                    (Test-NeuraOrdinaryDirectory -Path $_.FullName)
                } |
                Sort-Object -Property LastWriteTime -Descending
        )
        $keep = if ($RetainPerPlatform -gt 0) {
            @($runs | Select-Object -First $RetainPerPlatform -ExpandProperty Name)
        } else { @() }
        foreach ($run in ($runs | Sort-Object -Property LastWriteTime)) {
            if ($removed -ge $MaximumRemovals) { return }
            if ($run.Name -eq $currentRun -or
                $run.Name -in $keep -or
                $run.LastWriteTime -ge $cutoff) { continue }
            Write-Host ("Stale delivered package: {0} ({1:N2} GB)" -f
                $run.FullName, ((Get-NeuraDirectoryBytes -Path $run.FullName) / 1GB))
            if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $run.FullName }
            $removed++
        }
    }
}

function Invoke-NeuraStorageRecovery {
    param(
        [Parameter(Mandatory)][string]$ToolCache,
        [string]$RunnerTemp,
        [string[]]$PackageRoots = @(),
        [switch]$ReportOnly
    )
    $before = @{}
    foreach ($drive in [IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' }) {
        $before[$drive.Name] = $drive.AvailableFreeSpace
    }
    Invoke-NeuraRunnerRecovery -RunnerTemp $RunnerTemp -ReportOnly:$ReportOnly
    if (-not (Test-NeuraOrdinaryDirectory -Path $ToolCache)) {
        Write-Warning 'Runner tool cache is absent or linked; leaving it untouched.'
        return
    }

    $flutter = Join-Path $ToolCache 'flutter'
    if (Test-NeuraOrdinaryDirectory -Path $flutter) {
        foreach ($version in Get-ChildItem -LiteralPath $flutter -Directory -Force) {
            if ($version.Name -notmatch '^\d+\.\d+\.\d+$' -or
                -not (Test-NeuraOrdinaryDirectory -Path $version.FullName)) { continue }
            $stage = Join-Path $version.FullName '.install'
            if (-not (Test-NeuraOrdinaryDirectory -Path $stage)) { continue }
            if ($ReportOnly) {
                Write-Host ("Flutter staging (report only): {0} ({1:N2} GB)" -f
                    $stage, ((Get-NeuraDirectoryBytes -Path $stage) / 1GB))
                continue
            }
            $lock = $null
            try {
                # Use the installer's actual version lock. Age alone cannot
                # distinguish an abandoned extraction from a live install.
                $lockPath = Join-Path $flutter ".$($version.Name).install.lock"
                $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate,
                    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            } catch [IO.IOException] {
                Write-Host "Keeping active Flutter staging: $stage"
                continue
            }
            try {
                Write-Host ("Abandoned Flutter staging: {0} ({1:N2} GB)" -f
                    $stage, ((Get-NeuraDirectoryBytes -Path $stage) / 1GB))
                if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $stage }
            } finally {
                if ($lock) { $lock.Dispose() }
            }
        }
    }

    # The selected build volume owns all mutable Gradle state. Keep only
    # reusable wrapper distributions and dependency downloads in the persistent
    # tool cache; discard every other known Gradle directory when idle.
    $android = Join-Path $ToolCache 'neura-android'
    $gradle = Join-Path $android 'gradle-home'
    $caches = Join-Path $gradle 'caches'
    if ((Test-NeuraOrdinaryDirectory -Path $android) -and
        (Test-NeuraOrdinaryDirectory -Path $gradle)) {
        if (@(Get-Process -Name java, javaw -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-Host 'Keeping Gradle derived caches while a Java process is running.'
        } else {
            foreach ($entry in Get-ChildItem -LiteralPath $gradle -Directory -Force) {
                if ($entry.Name -in @('wrapper', 'caches') -or
                    -not (Test-NeuraOrdinaryDirectory -Path $entry.FullName)) { continue }
                Write-Host ("Disposable Gradle directory: {0} ({1:N2} GB)" -f
                    $entry.FullName, ((Get-NeuraDirectoryBytes -Path $entry.FullName) / 1GB))
                if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $entry.FullName }
            }
            if (Test-NeuraOrdinaryDirectory -Path $caches) {
                foreach ($entry in Get-ChildItem -LiteralPath $caches -Directory -Force) {
                    if ($entry.Name -eq 'modules-2' -or
                        -not (Test-NeuraOrdinaryDirectory -Path $entry.FullName)) { continue }
                    Write-Host ("Disposable Gradle cache: {0} ({1:N2} GB)" -f
                        $entry.FullName, ((Get-NeuraDirectoryBytes -Path $entry.FullName) / 1GB))
                    if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $entry.FullName }
                }
            }
        }
    }

    # Report only sizes inside known CI-owned roots. Never inspect personal
    # folders or delete installed SDKs, Flutter versions, or dependency jars.
    foreach ($entry in Get-ChildItem -LiteralPath $ToolCache -Directory -Force) {
        Write-Host ("Retained CI tools: {0} = {1:N2} GB" -f
            $entry.Name, ((Get-NeuraDirectoryBytes -Path $entry.FullName) / 1GB))
    }
    foreach ($packages in $PackageRoots) {
        if ([string]::IsNullOrWhiteSpace($packages)) { continue }
        Remove-NeuraStalePackageRuns -Root $packages -ReportOnly:$ReportOnly
        Write-Host ("Retained Neura packages at {0}: {1:N2} GB" -f
            $packages, ((Get-NeuraDirectoryBytes -Path $packages) / 1GB))
    }
    foreach ($name in $before.Keys) {
        $drive = [IO.DriveInfo]::new($name)
        Write-Host ("CI recovery volume {0}: before={1:N2} GB; after={2:N2} GB; reclaimed={3:N2} GB" -f
            $name, ($before[$name] / 1GB), ($drive.AvailableFreeSpace / 1GB),
            ([Math]::Max([long]0, [long]($drive.AvailableFreeSpace - $before[$name])) / 1GB))
    }
}

if ($ClearValidationOutput) {
    Clear-NeuraValidationOutput -RunRoot $ValidationRunRoot `
        -RunKey "$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT" -ReportOnly:$ReportOnly
    return
}

$packageRoots = @(
    [IO.DriveInfo]::GetDrives() |
        Where-Object {
            $_.IsReady -and
            ($_.DriveType -eq [IO.DriveType]::Fixed -or
             $_.DriveType -eq [IO.DriveType]::Removable)
        } |
        ForEach-Object { Join-Path $_.RootDirectory.FullName 'neura-packages' }
)
Invoke-NeuraStorageRecovery `
    -ToolCache $ToolCache `
    -RunnerTemp $RunnerTemp `
    -PackageRoots $packageRoots `
    -ReportOnly:$ReportOnly
