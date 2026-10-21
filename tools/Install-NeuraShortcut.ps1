#Requires -Version 5.1
<#
.SYNOPSIS
Creates "Neura" shortcuts, with Neura's avatar icon, on the Desktop and in the
Start menu. Each one runs the launcher (Neura.bat).
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

$targets = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Neura')
)

$shell = New-Object -ComObject WScript.Shell
foreach ($dir in $targets) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $path = Join-Path $dir 'Neura.lnk'
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $launcher
    $link.WorkingDirectory = $root
    $link.IconLocation = "$icon,0"
    $link.Description = 'Start Neura'
    $link.WindowStyle = 1
    $link.Save()
    if (-not $Quiet) { Write-Host "[Neura] Shortcut created: $path" -ForegroundColor Magenta }
}
