param(
  [string]$VsModulePath = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\share\cmake-3.31\Modules\FindPackageHandleStandardArgs.cmake",
  [string]$GoodModulePath = "C:\Program Files\CMake\share\cmake-4.2\Modules\FindPackageHandleStandardArgs.cmake",
  [string]$BackupDir = "$(Join-Path $env:USERPROFILE 'vs-cmake-module-backups')"
)

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
  Write-Host "Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow

  $argsList = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $PSCommandPath + '"'),
    '-VsModulePath', ('"' + $VsModulePath + '"'),
    '-GoodModulePath', ('"' + $GoodModulePath + '"'),
    '-BackupDir', ('"' + $BackupDir + '"')
  )

  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($argsList -join ' ')
  exit 0
}

if (-not (Test-Path -LiteralPath $VsModulePath)) {
  throw "VS module not found: $VsModulePath"
}

if (-not (Test-Path -LiteralPath $GoodModulePath)) {
  throw "Known-good module not found: $GoodModulePath"
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$timestamp = Get-Date -Format yyyyMMdd_HHmmss
$backupPath = Join-Path $BackupDir ("FindPackageHandleStandardArgs.cmake.vs.bak_$timestamp")

Copy-Item -LiteralPath $VsModulePath -Destination $backupPath -Force
Copy-Item -LiteralPath $GoodModulePath -Destination $VsModulePath -Force

"Backed up corrupted module to: $backupPath" | Write-Host
"Replaced VS module with: $GoodModulePath" | Write-Host

# Quick sanity: show first line of the replaced module
$firstLine = Get-Content -LiteralPath $VsModulePath -TotalCount 1
"VS module first line: $firstLine" | Write-Host
