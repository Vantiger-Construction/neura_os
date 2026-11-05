<#
.SYNOPSIS
Starts Neura with the opt-in Unity presence bridge.

.DESCRIPTION
Trusted launcher for the avatar presence relay (docs/NEURA_PRESENCE_BRIDGE.md):

1. Generates a fresh 64-hex session token in memory.
2. Starts neura_api on a numeric loopback port with the presence relay enabled
   (NEURA_API_PRESENCE_RELAY=1) and a cleared environment.
3. Starts the Unity presence prototype (player or Editor) and the Neura app,
   handing both the relay address and token through their child environment
   only. Nothing is written to disk, the registry or the command line.
4. When the Neura app exits, revokes the session and stops every child.

All children belong to a kill-on-close job, so closing this terminal stops them.
Without this launcher the app and Unity never connect to anything.

.EXAMPLE
pwsh tools/Start-NeuraPresenceBridge.ps1 -UnityExecutable 'C:\Builds\NeuraPresence\NeuraPresence.exe'

.EXAMPLE
pwsh tools/Start-NeuraPresenceBridge.ps1 `
  -UnityExecutable 'C:\Program Files\Unity\Hub\Editor\6000.6.6f1\Editor\Unity.exe' `
  -UnityArguments '-projectPath', (Resolve-Path prototypes\unity-presence)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UnityExecutable,
    [string[]]$UnityArguments = @(),
    [string]$AppExecutable,
    [string]$ApiExecutable
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
    throw 'This launcher requires 64-bit Windows PowerShell.'
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
if ([string]::IsNullOrWhiteSpace($AppExecutable)) { $AppExecutable = Join-Path $releaseDir 'neuro_companion.exe' }
if ([string]::IsNullOrWhiteSpace($ApiExecutable)) {
    $ApiExecutable = Join-Path $releaseDir 'neura_api.exe'
    if (-not (Test-Path -LiteralPath $ApiExecutable -PathType Leaf)) {
        $ApiExecutable = Join-Path $root 'rust\target\release\neura_api.exe'
    }
}
foreach ($required in @(
        @{ Path = $UnityExecutable; Hint = 'Build the Unity presence prototype or pass the Unity Editor path.' },
        @{ Path = $AppExecutable; Hint = 'Build the Windows app (flutter build windows) or pass -AppExecutable.' },
        @{ Path = $ApiExecutable; Hint = 'Build neura_api (cargo build --release --bin neura_api) or pass -ApiExecutable.' })) {
    if (-not (Test-Path -LiteralPath $required.Path -PathType Leaf)) { throw $required.Hint }
}
$UnityExecutable = (Resolve-Path -LiteralPath $UnityExecutable).ProviderPath
$AppExecutable = (Resolve-Path -LiteralPath $AppExecutable).ProviderPath
$ApiExecutable = (Resolve-Path -LiteralPath $ApiExecutable).ProviderPath

if (-not ('NeuraLocalConversationJob' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'NeuraLocalConversationProcess.cs')
}

function ConvertTo-NeuraArgument([string]$value) {
    if ($value -notmatch '[\s"]') { return $value }
    return '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Start-NeuraChild([string]$path, [string[]]$arguments, [hashtable]$extraEnvironment, [bool]$clearEnvironment) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $path
    $info.WorkingDirectory = Split-Path -Parent $path
    $info.UseShellExecute = $false
    $info.Arguments = (($arguments | ForEach-Object { ConvertTo-NeuraArgument $_ }) -join ' ')
    if ($clearEnvironment) {
        $info.EnvironmentVariables.Clear()
        $info.EnvironmentVariables['SystemRoot'] = $env:SystemRoot
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
    }
    foreach ($key in $extraEnvironment.Keys) { $info.EnvironmentVariables[$key] = $extraEnvironment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw "Could not start $(Split-Path -Leaf $path)." }
    $job.Attach($process)
    return $process
}

$job = $null
$api = $null
$unity = $null
$app = $null
$rng = $null
$token = $null
$address = $null
$bytes = New-Object byte[] 32
try {
    $job = [NeuraLocalConversationJob]::new()
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $token = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()

    $api = Start-NeuraChild $ApiExecutable @() @{
        NEURA_API_ADDR             = '127.0.0.1:0'
        NEURA_API_SESSION_TOKEN    = $token
        NEURA_API_PRESENCE_RELAY   = '1'
        NEURA_API_LAUNCHER_READY   = '1'
    } $true
    # Discard diagnostics; the relay never logs snapshots or credentials.
    $api.BeginErrorReadLine()
    $readLine = $api.StandardOutput.ReadLineAsync()
    if (-not $readLine.Wait([TimeSpan]::FromSeconds(20))) { throw 'neura_api did not report readiness.' }
    $ready = $readLine.Result
    if ($ready -cnotmatch '^NEURA_IPC_READY (127\.0\.0\.1:[1-9][0-9]{0,4})$') {
        throw 'neura_api reported an unexpected readiness receipt.'
    }
    $address = $Matches[1]

    $bridgeEnvironment = @{
        NEURA_PRESENCE_RELAY_ADDR = $address
        NEURA_PRESENCE_TOKEN      = $token
    }
    $unity = Start-NeuraChild $UnityExecutable $UnityArguments $bridgeEnvironment $false
    $app = Start-NeuraChild $AppExecutable @() $bridgeEnvironment $false
    Write-Host "Presence bridge running on $address. Close Neura to stop."
    $app.WaitForExit()
} finally {
    if ($api -and -not $api.HasExited -and $token -and $address) {
        try {
            Add-Type -AssemblyName System.Net.Http
            $handler = [Net.Http.HttpClientHandler]::new()
            $handler.UseProxy = $false
            $handler.AllowAutoRedirect = $false
            $http = [Net.Http.HttpClient]::new($handler)
            try {
                $http.Timeout = [TimeSpan]::FromSeconds(2)
                $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, "http://$address/session/revoke")
                $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
                $http.SendAsync($request).GetAwaiter().GetResult().Dispose()
            } finally { $http.Dispose() }
        } catch {
            # Closing the job below stops neura_api regardless.
        }
    }
    foreach ($process in @($app, $unity, $api)) {
        if ($process) {
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            $process.Dispose()
        }
    }
    if ($job) { $job.Dispose() }
    if ($rng) { $rng.Dispose() }
    [Array]::Clear($bytes, 0, $bytes.Length)
    $token = $null
}
