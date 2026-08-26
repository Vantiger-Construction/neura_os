#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(1, 168)]
    [int]$StaleHours = 6,
    [ValidateRange(1, 64)]
    [int]$MinimumFreeGb = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FreeBytes {
    param([Parameter(Mandatory)][string]$Path)

    $root = [System.IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "Cannot resolve the drive for: $Path"
    }

    $driveName = $root.TrimEnd('\').TrimEnd(':')
    return (Get-PSDrive -Name $driveName -ErrorAction Stop).Free
}

function Remove-EphemeralPath {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Write-Host "Removing ephemeral CI data: $Path" -ForegroundColor DarkGray
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "Could not completely remove $Path: $($_.Exception.Message)"
    }
}

$workspace = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$runnerWork = Split-Path -Parent (Split-Path -Parent $workspace)
$before = Get-FreeBytes -Path $workspace

Write-Host (
    "Runner free space before cleanup: {0:N2} GB" -f ($before / 1GB)
) -ForegroundColor Cyan

# Every path below is generated CI state. Source files, secure storage, Android
# SDKs, Flutter toolchains, and user-owned folders are intentionally excluded.
foreach ($repository in Get-ChildItem -LiteralPath $runnerWork -Directory -ErrorAction SilentlyContinue) {
    if ($repository.Name.StartsWith('_')) {
        continue
    }

    $checkout = Join-Path $repository.FullName $repository.Name
    Remove-EphemeralPath -Path (Join-Path $checkout 'build')
    Remove-EphemeralPath -Path (Join-Path $checkout 'rust\target')
}

$cleanupPaths = @(
    (Join-Path $workspace 'build'),
    (Join-Path $workspace 'rust\target'),
    (Join-Path $env:USERPROFILE '.gradle\caches'),
    (Join-Path $env:USERPROFILE '.gradle\daemon'),
    (Join-Path $env:USERPROFILE '.gradle\native'),
    (Join-Path $env:USERPROFILE '.gradle\notifications')
)
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $cleanupPaths += Join-Path $env:LOCALAPPDATA 'Pub\Cache\_temp'
}
foreach ($path in $cleanupPaths) {
    Remove-EphemeralPath -Path $path
}

$cutoff = (Get-Date).AddHours(-$StaleHours)
if (Test-Path -LiteralPath $env:RUNNER_TEMP -PathType Container) {
    Get-ChildItem -LiteralPath $env:RUNNER_TEMP -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            Remove-EphemeralPath -Path $_.FullName
        }
}

[GC]::Collect()
[GC]::WaitForPendingFinalizers()

$after = Get-FreeBytes -Path $workspace
$reclaimed = [Math]::Max(0, $after - $before)

Write-Host (
    "Runner free space after cleanup: {0:N2} GB (reclaimed {1:N2} GB)" -f
    ($after / 1GB),
    ($reclaimed / 1GB)
) -ForegroundColor Green

$minimum = [int64]$MinimumFreeGb * 1GB
if ($after -lt $minimum) {
    $message = (
        "The self-hosted runner has only {0:N2} GB free after safe cleanup; " +
        "{1} GB is required before compiling Flutter and Rust."
    ) -f ($after / 1GB), $MinimumFreeGb
    throw $message
}
