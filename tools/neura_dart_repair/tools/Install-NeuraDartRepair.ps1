[CmdletBinding()]
param([switch]$AllUsers, [switch]$Uninstall)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $PSScriptRoot
$installRoot = if ($AllUsers) { Join-Path $env:ProgramFiles 'Neura Dart Repair' } else { Join-Path $env:LOCALAPPDATA 'Programs\Neura Dart Repair' }
$startMenu = if ($AllUsers) { Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Neura' } else { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Neura' }

if ($Uninstall) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $startMenu 'Neura Dart Repair.lnk') -Force -ErrorAction SilentlyContinue
    Write-Host 'Neura Dart Repair uninstalled.' -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Get-ChildItem -LiteralPath $source -Force | Where-Object Name -notin @('installer') | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $installRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $startMenu -Force | Out-Null

$launcher = Join-Path $installRoot 'RUN_NEURA_REPAIR.cmd'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $startMenu 'Neura Dart Repair.lnk'))
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'Repair Neura Dart smart quotes and conservative string literal errors'
$shortcut.Save()

$desktop = [Environment]::GetFolderPath('Desktop')
$desktopShortcut = $shell.CreateShortcut((Join-Path $desktop 'Neura Dart Repair.lnk'))
$desktopShortcut.TargetPath = $launcher
$desktopShortcut.WorkingDirectory = $installRoot
$desktopShortcut.Description = $shortcut.Description
$desktopShortcut.Save()

Write-Host "Installed to: $installRoot" -ForegroundColor Green
Write-Host 'Shortcuts were added to the Start Menu and Desktop.' -ForegroundColor Green
