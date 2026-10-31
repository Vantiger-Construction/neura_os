#Requires -Version 5.1
<#
.SYNOPSIS
Read-only installed-bundle inspection and opt-in, user-observed speech evidence.
.DESCRIPTION
Never launches Neura, builds software, changes app data/settings, enables a mic,
downloads voices, configures WER, kills processes or uploads evidence. Only a
new report directory is written. Reuses tools/windows_tts_smoke.dart for manual
playback; no second speech engine or speech harness is introduced.
#>
[CmdletBinding()]
param(
    [string]$ExePath,
    [string]$SourceRoot,
    [string]$OutputParent = $PSScriptRoot,
    [ValidateSet('Unknown', 'Debug', 'Release')][string]$Configuration = 'Unknown',
    [ValidateSet('Unknown', 'Production', 'Harness')][string]$EntryPoint = 'Unknown',
    [ValidateRange(0, 2147483647)][int]$AppProcessId = 0,
    [switch]$Observe
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'NeuraSpeechEvidence.psm1') -Force

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This entry point requires Windows. Synthetic helper tests are separate.'
}
if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = (Read-Host 'Paste the full path to the installed neuro_companion.exe').Trim().Trim('"')
}
$exe = Get-NeuraPlainItem $ExePath
$outputItem = Get-NeuraPlainItem $OutputParent
if (-not $outputItem.PSIsContainer) { throw 'Choose an existing output directory.' }
$bundlePrefix = $exe.DirectoryName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (($outputItem.FullName + [IO.Path]::DirectorySeparatorChar).StartsWith($bundlePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Keep the helper and output directory outside the application bundle.'
}
$output = Join-Path $outputItem.FullName ('Neura-Speech-Results-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $output)
$start = [datetime]::UtcNow.AddMinutes(-15)
$scenarios = @(
    @{ id = 'cold_start_and_first_speech'; repetitions = 10; applies = 'Both'
        procedure = 'Ten cold launches: startup stays silent, then fixed short/sample speech is audible and complete. Production includes normal mascot lifecycle.' },
    @{ id = 'repeated_speech'; repetitions = 20; applies = 'Both'
        procedure = 'Twenty sequential short fixed samples: complete audio, no freeze/error and speech focus clears.' },
    @{ id = 'replacement'; repetitions = 10; applies = 'Harness'
        procedure = 'Ten long-to-short replacements, including immediate replacement before first audio. No overlap or old audio resuming; latest finishes and focus clears.' },
    @{ id = 'stop_then_fresh_speech'; repetitions = 10; applies = 'Harness'
        procedure = 'Ten long -> Stop -> fresh short cycles. Silence after Stop; no stale callback cuts off fresh speech; focus clears.' },
    @{ id = 'safe_mode'; repetitions = 10; applies = 'Both'
        procedure = 'Enter Safe Mode during first-use/long speech. Audio stops and mic remains off. Exit without Speak: no restart. Repeat ten times.' },
    @{ id = 'background_and_shutdown'; repetitions = 10; applies = 'Both'
        procedure = 'Minimize/deactivate during speech and close immediately after a first request, ten cycles. No old audio resumes, freeze or teardown crash. Reopen requires fresh explicit Speak.' },
    @{ id = 'preview_disposal'; repetitions = 10; applies = 'Production'
        procedure = 'Close Voice Settings while its fixed preview plays, ten cycles. Preview stops without lingering audio or stuck ambient ducking.' },
    @{ id = 'chat_reply'; repetitions = 10; applies = 'Production'
        procedure = 'In an isolated synthetic profile, use typed offline chat and the existing local reply-speech setting. Ten replies: expected audible speech; Stop/replacement works. No cloud/mic. Restore setting in test profile afterward.' },
    @{ id = 'alternate_voice_and_output'; repetitions = 1; applies = 'Both'
        procedure = 'Repeat short/Stop using another installed Microsoft desktop voice and a controlled output change. If unavailable, leave NOT RUN.' }
)
$rows = @($scenarios | ForEach-Object { [pscustomobject]@{
    scenario = $_.id; status = 'NOT RUN'; repetitions = 0; minimum_repetitions = $_.repetitions
    observation_source = 'NONE'; applies_to = $_.applies; procedure = $_.procedure
} })
$report = [ordered]@{
    schema = 1; created_utc = [datetime]::UtcNow.ToString('o')
    inspected_reference_commit = 'dd6a53f7bc25f751a48e23087e5040c95125a588'
    ci = @{ result = 'PREVIOUSLY_VERIFIED_NOT_REEXECUTED'; run = 39868591948
        head = '125d278e5d7bc8a442f22c6b5050adf0b74414d6'; physical_speech = 'NOT RUN' }
    environment = @{ os_version = [Environment]::OSVersion.Version.ToString(); powershell = $PSVersionTable.PSVersion.ToString()
        configuration = $Configuration; entry_point = $EntryPoint; physical_machine = 'UNVERIFIED' }
    bundle = @{ status = 'NOT_INSPECTED' }; source = @{ status = 'NOT_PROVIDED' }
    loaded_modules = @{ status = 'NOT_REQUESTED' }
    diagnostics = @{ status = 'NOT_COLLECTED' }; physical_results = $rows
    acceptance = 'PENDING_PHYSICAL_WINDOWS_EVIDENCE'
    privacy = 'Only allowlisted metadata and hashes. No app data, transcripts, usernames, machine names, full paths, raw logs, audio or dumps.'
}

function Save-Report {
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $output 'speech-evidence.json') -Encoding UTF8
    $lines = @('# Neura Windows speech evidence', '',
        ('Static bundle: **{0}**. This is not audible or crash acceptance.' -f $report.bundle.status),
        ('Executable SHA-256: `{0}`' -f $(if ($report.bundle.status -in @('PASS', 'FAIL')) { $report.bundle.executable.sha256 } else { 'unavailable' })),
        ('Build: {0}; entry point: {1}; physical machine: {2} (operator labels).' -f
            $report.environment.configuration, $report.environment.entry_point, $report.environment.physical_machine),
        '', 'CI is recorded separately: previously verified run 39868591948; no physical speech executed.',
        'Commit provenance of the inspected executable remains unverified. Source hashes do not bind a binary to a commit.',
        '', '| Physical scenario | Result | Repetitions |', '| --- | --- | --- |')
    foreach ($row in $rows) { $lines += '| {0} | {1} | {2}/{3} |' -f $row.scenario, $row.status, $row.repetitions, $row.minimum_repetitions }
    $lines += @('', 'See speech-evidence.json for filtered diagnostics and exact file hashes.',
        'PASS rows are operator observations. Missing/unreadable logs and a visible window never establish acceptance.',
        'Keep issue #32 open pending both configurations, both entry points, diagnostic review and matching bundle/symbol evidence.',
        'Keep startup greetings disabled and microphone restrictions intact. Keep full dumps and symbols private.')
    $lines | Set-Content -LiteralPath (Join-Path $output 'READ-RESULTS.md') -Encoding UTF8
}

try {
    $report.bundle = Get-NeuraBundleEvidence $exe.FullName
} catch { $report.bundle = @{ status = 'INCOMPLETE'; reason = 'Read failed, malformed input, link or inspection bound; no paths exported' } }
try { $report.source = Get-NeuraSourceEvidence $SourceRoot (Join-Path $PSScriptRoot 'source-reference.json') }
catch { $report.source = @{ status = 'INCOMPLETE' } }

# An optional snapshot of an already running, explicitly selected process.
# Never infer permission to launch, terminate or open a different application's modules.
if ($AppProcessId -gt 0) {
    try {
        $process = Get-Process -Id $AppProcessId -ErrorAction Stop
        if (-not [string]::Equals($process.MainModule.FileName, $exe.FullName, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Selected process does not match the inspected executable.'
        }
        $names = @($process.Modules | ForEach-Object { $_.ModuleName.ToLowerInvariant() })
        $report.loaded_modules = @{ status = 'SNAPSHOT_ONLY'; sapi_loaded = $names -contains 'sapi.dll'
            legacy_loaded = $names -contains 'flutter_tts_plugin.dll'
            executable_sha256 = (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    } catch { $report.loaded_modules = @{ status = 'UNAVAILABLE_OR_MISMATCH' } }
}
$report.preflight = if ($report.bundle.status -ne 'PASS' -or $report.loaded_modules.status -eq 'UNAVAILABLE_OR_MISMATCH') {
    'INCOMPLETE_OR_FAILED'
} elseif ($report.loaded_modules.status -eq 'SNAPSHOT_ONLY' -and $report.loaded_modules.legacy_loaded) {
    'LEGACY_MODULE_LOADED'
} else { 'STATIC_CHECKS_PASSED' }
Save-Report

if ($Observe -and $report.preflight -eq 'STATIC_CHECKS_PASSED') {
    Write-Host 'This helper never launches Neura. Use only an isolated Windows test account with synthetic data.'
    Write-Host 'Keep network disconnected, microphone/wake-word capture off, and startup greetings disabled.'
    Write-Host 'Use the existing fixed-text harness for controlled Stop/replacement; use production Neura for mascot/chat/preview checks.'
    $ready = Read-Host 'Are those conditions in place on a physical Windows PC with working audio? Type YES, or Enter to skip'
    if ($ready -ceq 'YES') {
        $report.environment.physical_machine = 'SELF_REPORTED_PHYSICAL'
        if ($Configuration -eq 'Unknown') {
            $choice = Read-Host 'Build configuration: D=Debug, R=Release, Enter=unknown'
            if ($choice -ieq 'D') { $report.environment.configuration = 'Debug' }
            if ($choice -ieq 'R') { $report.environment.configuration = 'Release' }
        }
        if ($EntryPoint -eq 'Unknown') {
            $choice = Read-Host 'Entry point: P=production app, H=existing fixed-text harness, Enter=unknown'
            if ($choice -ieq 'P') { $report.environment.entry_point = 'Production' }
            if ($choice -ieq 'H') { $report.environment.entry_point = 'Harness' }
        }
        $start = [datetime]::UtcNow
        foreach ($row in $rows) {
            if ($row.applies_to -ne 'Both' -and $row.applies_to -ne $report.environment.entry_point) { continue }
            Write-Host ("`n" + $row.scenario + ': ' + $row.procedure)
            $choice = Read-Host 'After exercising this scenario: P=observed pass, F=any failure, Enter=not run'
            if ($choice -notin @('P', 'F')) { continue }
            $count = 0
            [void][int]::TryParse((Read-Host 'Number of repetitions actually completed'), [ref]$count)
            $row.repetitions = [Math]::Max(0, [Math]::Min($count, 1000))
            $row.observation_source = 'OPERATOR_REPORT_NOT_AUTOMATICALLY_VERIFIED'
            $row.status = if ($choice -ieq 'F') { 'FAIL' } elseif ($count -lt $row.minimum_repetitions) { 'PARTIAL' } else { 'PASS' }
            Save-Report
            if ($row.status -eq 'FAIL') {
                Write-Host 'Stop this session. Preserve the exact bundle and matching symbols privately; do not repeat a demonstrated crash.'
                break
            }
        }
    }
} elseif ($Observe) { Write-Host 'Bundle inspection did not pass. Do not start speech testing with this bundle.' }

$end = [datetime]::UtcNow
if (($end - $start).TotalHours -le 4) {
    $report.diagnostics = @{
        start_utc = $start.ToString('o'); end_utc = $end.ToString('o')
        window_kind = $(if ($report.environment.physical_machine -eq 'SELF_REPORTED_PHYSICAL') { 'OBSERVED_SESSION' } else { 'RECENT_DIAGNOSTICS_ONLY' })
        windows_events = Get-NeuraEventEvidence $exe.FullName $start $end
        native_breadcrumbs = Get-NeuraNativeEvidence ([IO.Path]::GetTempPath()) $start $end
    }
} else { $report.diagnostics = @{ status = 'INTERVAL_EXCEEDED_FOUR_HOURS' } }
try {
    $report.bundle_after = Get-NeuraBundleEvidence $exe.FullName
    # Full identity comparison includes AOT/debug payload and symbols, not only the launcher EXE.
    $before = $report.bundle | ConvertTo-Json -Depth 8 -Compress
    $after = $report.bundle_after | ConvertTo-Json -Depth 8 -Compress
    $report.bundle_unchanged = $before -ceq $after
} catch { $report.bundle_unchanged = $false }
Save-Report
Write-Host "`nResults saved to: $output"
Write-Host 'Review speech-evidence.json and READ-RESULTS.md before sharing. Nothing has been uploaded.'
if ($report.preflight -ne 'STATIC_CHECKS_PASSED' -or -not $report.bundle_unchanged) { exit 2 }
exit 0
