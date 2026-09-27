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
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    # Never traverse junctions or symbolic links, including nested ones.
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Write-Warning "Keeping linked cache entry: $Path"
        return
    }
    try {
        if ($item.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop) {
                Remove-NeuraDerivedTree -Path $child.FullName
            }
            if (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop).Count -ne 0) {
                return
            }
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Write-Warning "Keeping unavailable cache entry ${Path}: $($_.Exception.Message)"
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

function Invoke-NeuraStorageRecovery {
    param(
        [Parameter(Mandatory)][string]$ToolCache,
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

    # Android uses this explicit CI cache, not USERPROFILE\.gradle. Retain
    # downloaded dependencies, Gradle distributions, JDK, SDK, and NDK.
    $android = Join-Path $ToolCache 'neura-android'
    $gradle = Join-Path $android 'gradle-home'
    $caches = Join-Path $gradle 'caches'
    if ((Test-NeuraOrdinaryDirectory -Path $android) -and
        (Test-NeuraOrdinaryDirectory -Path $gradle) -and
        (Test-NeuraOrdinaryDirectory -Path $caches)) {
        if (@(Get-Process -Name java, javaw -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-Host 'Keeping Gradle derived caches while a Java process is running.'
        } else {
            foreach ($entry in Get-ChildItem -LiteralPath $caches -Directory -Force) {
                if (-not (Test-NeuraOrdinaryDirectory -Path $entry.FullName)) { continue }
                $candidate = $null
                if ($entry.Name -match '^(build-cache|transforms)-\d+$') {
                    $candidate = $entry.FullName
                } elseif ($entry.Name -match '^\d+\.\d+(\.\d+)?$') {
                    $candidate = Join-Path $entry.FullName 'transforms'
                }
                if ($candidate -and (Test-NeuraOrdinaryDirectory -Path $candidate)) {
                    Write-Host ("Disposable Gradle output: {0} ({1:N2} GB)" -f
                        $candidate, ((Get-NeuraDirectoryBytes -Path $candidate) / 1GB))
                    if (-not $ReportOnly) { Remove-NeuraDerivedTree -Path $candidate }
                }
            }
        }
    }

    # Report only sizes inside known CI-owned roots. Never inspect personal
    # folders or delete retained packages, installed SDKs, or dependency jars.
    foreach ($entry in Get-ChildItem -LiteralPath $ToolCache -Directory -Force) {
        Write-Host ("Retained CI tools: {0} = {1:N2} GB" -f
            $entry.Name, ((Get-NeuraDirectoryBytes -Path $entry.FullName) / 1GB))
    }
    $volume = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($ToolCache))
    $packages = Join-Path $volume 'neura-packages'
    Write-Host ("Retained Neura packages: {0:N2} GB" -f
        ((Get-NeuraDirectoryBytes -Path $packages) / 1GB))
}

Invoke-NeuraStorageRecovery -ToolCache $ToolCache -ReportOnly:$ReportOnly
