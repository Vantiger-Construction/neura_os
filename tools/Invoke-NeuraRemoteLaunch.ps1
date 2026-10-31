#Requires -Version 5.1
<#
.SYNOPSIS
Runs inside the signed-in Windows session (via the "Neura Remote Launch"
scheduled tasks) and starts Neura on the desktop.

.DESCRIPTION
The GitHub Actions runner cannot show a window on the desktop: it may run as a
service in session 0, and it ends every process a job starts when the job
finishes. So the remote-launch workflow only starts a scheduled task that
Register-NeuraRemoteLaunch.ps1 created for the signed-in user, and that task
runs this script in the user's own session.

  -Mode launch   Start Neura with tools\Start-Neura.ps1 (it rebuilds only
                 when sources changed and exits if Neura is already running).
  -Mode update   Fast-forward this checkout from origin first, but only when
                 the working tree is clean and the branch has an upstream;
                 otherwise it skips the update, logs why, and launches anyway.

Every run appends to %LOCALAPPDATA%\Neura\remote-launch.log.
#>
[CmdletBinding()]
param(
    [ValidateSet('launch', 'update')]
    [string]$Mode = 'launch'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $env:LOCALAPPDATA 'Neura'
$logFile = Join-Path $logDir 'remote-launch.log'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-Log([string]$Text) {
    $line = '{0:u} [{1}] {2}' -f (Get-Date), $Mode, $Text
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $root @Arguments 2>&1 | ForEach-Object { "$_" }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = @($output) }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Update-Checkout {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log 'git is not on PATH; skipping update.'
        return
    }
    $dirty = (Invoke-Git @('status', '--porcelain', '--untracked-files=no')).Output |
        Where-Object { $_ }
    if ($dirty) {
        Write-Log 'Working tree has uncommitted changes; skipping update.'
        return
    }
    $upstream = Invoke-Git @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    if ($upstream.Code -ne 0) {
        Write-Log 'Current branch has no upstream; skipping update.'
        return
    }
    $pull = Invoke-Git @('pull', '--ff-only')
    Write-Log ("git pull --ff-only exited {0}: {1}" -f $pull.Code, ($pull.Output -join ' | '))
}

try {
    Write-Log "Requested in $root"
    if ($Mode -eq 'update') { Update-Checkout }

    $launcher = Join-Path $PSScriptRoot 'Start-Neura.ps1'
    & $launcher
    Write-Log 'Start-Neura.ps1 finished.'
} catch {
    Write-Log "Failed: $($_.Exception.Message)"
    throw
}
