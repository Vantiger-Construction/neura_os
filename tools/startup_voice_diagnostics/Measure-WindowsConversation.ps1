#Requires -Version 5.1
<#
.SYNOPSIS
Sample an already-running, hash-identified Neura process without opening audio.
.DESCRIPTION
Start this collector, then bring Neura to the foreground for the trial. Do not
switch to this console during hands-free use: focus loss intentionally cancels
the app session. The collector never starts/stops an app or model, changes
permissions, reads chat/command lines, uploads, or opens microphone/speaker APIs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$NeuraProcessId,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedExeSha256,
    [Parameter(Mandatory)][string]$OutputFile,
    [ValidateRange(600,1800)][int]$DurationSeconds = 660,
    [ValidateRange(1,10)][int]$IntervalSeconds = 2
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Windows is required; hardware acceptance remains NOT RUN.'
}
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell.' }
if (Test-Path -LiteralPath $OutputFile) { throw 'Choose a new output file.' }
$app = Get-Process -Id $NeuraProcessId -ErrorAction Stop
if ($app.ProcessName -cne 'neuro_companion') { throw 'Select the Neura application process.' }
$started = $app.StartTime.ToUniversalTime()
$exe = $app.Path
if ([string]::IsNullOrWhiteSpace($exe) -or
    (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedExeSha256) {
    throw 'Application executable does not match the independently verified package.'
}
$total = [long](Get-CimInstance Win32_ComputerSystem -Property TotalPhysicalMemory).TotalPhysicalMemory
if ($total -le 0) { throw 'Physical memory inventory unavailable.' }
$full = [IO.Path]::GetFullPath($OutputFile)
if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($full)) -PathType Container)) {
    throw 'Create a new local evidence directory first.'
}
$stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
$writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($false)))
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    $writer.WriteLine('elapsed_ms,utc,executable_sha256,total_physical_bytes,available_physical_bytes,neura_working_set_bytes,matching_ollama_working_set_bytes,matching_ollama_processes')
    $writer.Flush()
    Write-Host 'Sampling only. Bring Neura to the foreground now; leave this collector running.'
    Write-Host 'No microphones, speech, inference, downloads or uploads are started by this collector.'
    while ($true) {
        $current = Get-Process -Id $NeuraProcessId -ErrorAction Stop
        if ($current.StartTime.ToUniversalTime() -ne $started -or $current.ProcessName -cne 'neuro_companion') {
            throw 'The observed process changed. Stop and create a new trial record.'
        }
        $free = [long](Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory).FreePhysicalMemory * 1024
        $modelBytes = [long]0
        $modelCount = 0
        foreach ($name in @('ollama', 'ollama_llama_server', 'ollama_runner', 'llama-server', 'llama-runner')) {
            foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                try { $modelBytes += [long]$process.WorkingSet64; $modelCount++ } catch { }
            }
        }
        $writer.WriteLine(('{0},{1},{2},{3},{4},{5},{6},{7}' -f
            $timer.ElapsedMilliseconds, [datetime]::UtcNow.ToString('o'), $ExpectedExeSha256,
            $total, $free, [long]$current.WorkingSet64, $modelBytes, $modelCount))
        $writer.Flush()
        if ($timer.Elapsed.TotalSeconds -ge $DurationSeconds) { break }
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    $timer.Stop()
    $writer.Dispose()
    $stream.Dispose()
}
Write-Host 'Sample capture completed. This is not microphone, inference, or physical acceptance.'
Write-Host 'Working sets are sampled; unrecognized model processes and GPU memory are excluded.'
