#Requires -Version 5.1
<#
.SYNOPSIS
One-time setup so the "Neura Remote Launch" workflow (and the Slack /neura
command) can open Neura on this PC's desktop.

.DESCRIPTION
Registers two scheduled tasks for the signed-in user:

  Neura Remote Launch          -> Invoke-NeuraRemoteLaunch.ps1 -Mode launch
  Neura Remote Launch (Update) -> Invoke-NeuraRemoteLaunch.ps1 -Mode update

Both run only while you are signed in, in your own desktop session, without
elevation. Their security descriptor also lets the account the Actions runner
uses read and run them (nothing else), so the workflow can start them even when
the runner is a Windows service.

Run it from the checkout Neura should launch from. Re-run it after moving the
checkout. -Unregister removes both tasks.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tools\Register-NeuraRemoteLaunch.ps1
.EXAMPLE
powershell -ExecutionPolicy Bypass -File tools\Register-NeuraRemoteLaunch.ps1 -RunnerAccount 'NT AUTHORITY\NETWORK SERVICE'
#>
[CmdletBinding()]
param(
    # Account the GitHub Actions runner runs as. Default: auto-detected from
    # the actions.runner.* service, else the current user (interactive runner).
    [string]$RunnerAccount,
    [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tasks = [ordered]@{
    'Neura Remote Launch'          = 'launch'
    'Neura Remote Launch (Update)' = 'update'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$invoker = Join-Path $PSScriptRoot 'Invoke-NeuraRemoteLaunch.ps1'
if (-not (Test-Path -LiteralPath $invoker -PathType Leaf)) {
    throw "Missing $invoker"
}

$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
# Root task folder: creating a sub-folder can need admin rights.
$folder = $service.GetFolder('\')

if ($Unregister) {
    foreach ($name in $tasks.Keys) {
        try {
            $folder.DeleteTask($name, 0)
            Write-Host "Removed $name"
        } catch {
            Write-Host "Not registered: $name"
        }
    }
    return
}

function Resolve-Sid([string]$Account) {
    $nt = New-Object System.Security.Principal.NTAccount($Account)
    return $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

$userAccount = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

if (-not $RunnerAccount) {
    $runnerService = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'actions.runner.*' } |
        Select-Object -First 1
    if ($runnerService) {
        $RunnerAccount = $runnerService.StartName
        Write-Host "Actions runner service '$($runnerService.Name)' runs as $RunnerAccount"
    } else {
        $RunnerAccount = $userAccount
        Write-Host "No runner service found; assuming the runner runs as you ($userAccount)."
    }
}
switch -Regex ($RunnerAccount) {
    '^(LocalSystem|\.\\LocalSystem)$' { $RunnerAccount = 'NT AUTHORITY\SYSTEM' }
    '^NT AUTHORITY\\NetworkService$' { $RunnerAccount = 'NT AUTHORITY\NETWORK SERVICE' }
    '^NT AUTHORITY\\LocalService$'   { $RunnerAccount = 'NT AUTHORITY\LOCAL SERVICE' }
}
$runnerSid = Resolve-Sid $RunnerAccount

# Owner and you: full control. SYSTEM and Administrators: full control.
# The runner account: read + execute only (enough to start the task).
$sddl = "O:${userSid}D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;FA;;;${userSid})(A;;GRGX;;;${runnerSid})"

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

foreach ($name in $tasks.Keys) {
    $mode = $tasks[$name]
    $def = $service.NewTask(0)
    $def.RegistrationInfo.Description =
        "Opens Neura on this desktop when the 'Neura Remote Launch' GitHub workflow runs (mode: $mode)."
    $def.Principal.UserId = $userAccount
    $def.Principal.LogonType = 3   # TASK_LOGON_INTERACTIVE_TOKEN: only while signed in, in your session
    $def.Principal.RunLevel = 0    # TASK_RUNLEVEL_LUA: no elevation
    $def.Settings.Enabled = $true
    $def.Settings.AllowDemandStart = $true
    $def.Settings.StartWhenAvailable = $false
    $def.Settings.DisallowStartIfOnBatteries = $false
    $def.Settings.StopIfGoingOnBatteries = $false
    $def.Settings.MultipleInstances = 2   # TASK_INSTANCES_IGNORE_NEW
    $def.Settings.ExecutionTimeLimit = 'PT1H'
    $def.Settings.Hidden = $false

    $action = $def.Actions.Create(0)  # TASK_ACTION_EXEC
    $action.Path = $powershell
    $action.Arguments =
        "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$invoker`" -Mode $mode"
    $action.WorkingDirectory = $root

    # 6 = TASK_CREATE_OR_UPDATE, 3 = TASK_LOGON_INTERACTIVE_TOKEN
    try {
        [void]$folder.RegisterTaskDefinition($name, $def, 6, $null, $null, 3, $sddl)
        Write-Host "Registered $name -> $mode (runner may start it)"
    } catch {
        Write-Warning ("Windows refused the custom permissions ({0}); registering " +
            "with default permissions. That works when the runner runs as you or " +
            "as SYSTEM; otherwise re-run this script from an elevated PowerShell." -f
            $_.Exception.Message)
        [void]$folder.RegisterTaskDefinition($name, $def, 6, $null, $null, 3, $null)
        Write-Host "Registered $name -> $mode (default permissions)"
    }
}

Write-Host ''
Write-Host "Neura will launch from: $root"
Write-Host "Runner account allowed to start the tasks: $RunnerAccount"
Write-Host 'Test it now:  Start-ScheduledTask -TaskName "Neura Remote Launch"'
