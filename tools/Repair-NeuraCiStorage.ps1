#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ToolCache = $env:RUNNER_TOOL_CACHE,
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
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction SilentlyContinue) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $bytes += $item.Length }
        }
    }
    return $bytes
}

function Remove-NeuraStalePackageRuns {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$RetainPerPlatform = 3,
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
        $keep = @($runs | Select-Object -First $RetainPerPlatform -ExpandProperty Name)
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
        [string[]]$PackageRoots = @(),
        [switch]$ReportOnly
    )
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
    -PackageRoots $packageRoots `
    -ReportOnly:$ReportOnly

