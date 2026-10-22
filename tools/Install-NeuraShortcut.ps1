#Requires -Version 5.1
<#
.SYNOPSIS
Ensures owned "Neura" shortcuts exist on the shell-resolved Desktop and Start
menu. Correct shortcuts are left unchanged; stale Neura shortcuts are repaired.
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$launcher = Join-Path $root 'Neura.bat'
$icon = Join-Path $root 'windows\runner\resources\app_icon.ico'
$buildDir = Join-Path $root 'build'
$shortcutLockFile = Join-Path $buildDir 'neura_shortcut.lock'

function Get-NormalizedShortcutPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        return [IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($Path)
        ).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

if (Test-Path -LiteralPath $buildDir) {
    $buildItem = Get-Item -LiteralPath $buildDir -Force
    if (-not $buildItem.PSIsContainer -or
        ($buildItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing unsafe build directory: $buildDir"
    }
} else {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}
if (Test-Path -LiteralPath $shortcutLockFile) {
    $lockItem = Get-Item -LiteralPath $shortcutLockFile -Force
    if ($lockItem.PSIsContainer -or
        ($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing unsafe shortcut lock: $shortcutLockFile"
    }
}
$shortcutLock = $null
try {
    $shortcutLock = [IO.File]::Open(
        $shortcutLockFile,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
} catch [IO.IOException] {
    if (-not $Quiet) {
        Write-Host '[Neura] Shortcut repair is already in progress.' `
            -ForegroundColor DarkGray
    }
    return
}

try {

$targets = @(
    [PSCustomObject]@{
        Label = 'Desktop'
        Directory = [Environment]::GetFolderPath('Desktop')
    },
    [PSCustomObject]@{
        Label = 'Start menu'
        Directory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Neura'
    }
)

$shell = New-Object -ComObject WScript.Shell
foreach ($target in $targets) {
    $dir = [string]$target.Directory
    if ([string]::IsNullOrWhiteSpace($dir)) {
        Write-Warning "$($target.Label) folder is unavailable; shortcut was not changed."
        continue
    }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $path = Join-Path $dir 'Neura.lnk'
    $needsWrite = $true
    if (Test-Path -LiteralPath $path) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Warning "Keeping non-file shortcut path: $path"
            continue
        }
        $shortcutItem = Get-Item -LiteralPath $path -Force
        if (($shortcutItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Warning "Keeping linked shortcut path: $path"
            continue
        }
        $existing = $shell.CreateShortcut($path)
        $owned = (
            $existing.Description -ceq 'Start Neura' -or
            [IO.Path]::GetFileName($existing.TargetPath) -ieq 'Neura.bat'
        )
        if (-not $owned) {
            Write-Warning "Keeping unrelated existing shortcut: $path"
            continue
        }

        $needsWrite = (
            (Get-NormalizedShortcutPath $existing.TargetPath) -ine
                (Get-NormalizedShortcutPath $launcher) -or
            (Get-NormalizedShortcutPath $existing.WorkingDirectory) -ine
                (Get-NormalizedShortcutPath $root) -or
            $existing.IconLocation -ine "$icon,0" -or
            -not [string]::IsNullOrWhiteSpace([string]$existing.Arguments) -or
            $existing.Description -cne 'Start Neura' -or
            [int]$existing.WindowStyle -ne 1
        )
    }

    if ($needsWrite) {
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $launcher
        $link.WorkingDirectory = $root
        $link.IconLocation = "$icon,0"
        $link.Arguments = ''
        $link.Description = 'Start Neura'
        $link.WindowStyle = 1
        $link.Save()
        if (-not $Quiet) {
            Write-Host "[Neura] Shortcut created or repaired: $path" -ForegroundColor Magenta
        }
    } elseif (-not $Quiet) {
        Write-Host "[Neura] Shortcut already current: $path" -ForegroundColor DarkGray
    }
}
} finally {
    $shortcutLock.Dispose()
}
