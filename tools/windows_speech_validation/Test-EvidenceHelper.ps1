#Requires -Version 5.1
# Synthetic safety tests only. No Neura executable is launched or speech/mic used.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'NeuraSpeechEvidence.psm1') -Force
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('neura-speech-fixtures-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $scratch)
$script:checks = 0
function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Write-Fixture([string]$Path, [switch]$Legacy, [switch]$MissingSapi) {
    # Deliberately non-executable bytes: sufficient PE metadata and fixed markers
    # exercise inspection without any loader, native instructions or COM engine.
    $bytes = New-Object byte[] 4096
    $bytes[0] = 0x4d; $bytes[1] = 0x5a
    [BitConverter]::GetBytes([int]128).CopyTo($bytes, 60)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 128)
    [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes, 132)
    $offset = 256
    $text = if ($MissingSapi) { 'not the SAPI implementation' } else {
        "neura/speech_synthesis`0local_speech_unavailable`0No local desktop voice installed`0Local speech requires an application restart.`0"
    }
    if ($Legacy) { $text += 'FlutterTtsPluginRegisterWithRegistrar flutter_tts_plugin.dll' }
    $part = [Text.Encoding]::ASCII.GetBytes($text); $part.CopyTo($bytes, $offset); $offset += $part.Length
    if (-not $MissingSapi) {
        $part = [Text.Encoding]::Unicode.GetBytes("Vendor=Microsoft`0TTS_MS_"); $part.CopyTo($bytes, $offset); $offset += $part.Length
        ([Guid]'96749377-3391-11d2-9ee3-00c04f797396').ToByteArray().CopyTo($bytes, $offset)
    }
    [IO.File]::WriteAllBytes($Path, $bytes)
}
try {
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') }) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        Require (@($errors).Count -eq 0) 'PowerShell syntax failure.'
    }
    $bundle = Join-Path $scratch 'bundle'
    [void](New-Item -ItemType Directory -Path (Join-Path $bundle 'data') -Force)
    $exe = Join-Path $bundle 'neuro_companion.exe'
    Write-Fixture $exe
    Write-Fixture (Join-Path $bundle 'flutter_windows.dll') -MissingSapi
    [IO.File]::WriteAllText((Join-Path $bundle 'data/icudtl.dat'), 'synthetic')
    $result = Get-NeuraBundleEvidence $exe
    Require ($result.status -eq 'PASS') 'Clean static SAPI fixture should match.'
    Require ($result.commit_provenance -eq 'UNVERIFIED') 'Static bytes must not invent commit provenance.'
    Require ($result.executable.sha256.Length -eq 64) 'Executable identity was not hashed.'
    Write-Fixture $exe -MissingSapi
    Require ((Get-NeuraBundleEvidence $exe).status -eq 'FAIL') 'Old/non-SAPI executable must fail.'
    Write-Fixture $exe -Legacy
    Require ((Get-NeuraBundleEvidence $exe).status -eq 'FAIL') 'Legacy registration/import indicator must fail.'
    Write-Fixture $exe
    $nested = Join-Path $bundle 'nested'; [void](New-Item -ItemType Directory -Path $nested)
    $legacy = Join-Path $nested 'FLUTTER_TTS_PLUGIN.DLL'; Write-Fixture $legacy
    Require ((Get-NeuraBundleEvidence $exe).legacy_dll_bundled) 'Nested/case-varied legacy DLL must be detected.'
    Remove-Item -LiteralPath $legacy
    $unknown = Join-Path $nested 'PRIVATE_PERSON_SECRET.dll'; Write-Fixture $unknown -Legacy
    $result = Get-NeuraBundleEvidence $exe
    Require ($result.status -eq 'FAIL') 'Renamed native DLL containing legacy markers must fail.'
    Require ((($result | ConvertTo-Json -Depth 8) -notmatch 'PRIVATE_PERSON_SECRET')) 'Unexpected filenames must not be exported.'
    Remove-Item -LiteralPath $unknown
    [IO.File]::WriteAllText($unknown, 'not a PE')
    $rejected = $false
    try { [void](Get-NeuraBundleEvidence $exe) } catch { $rejected = $true }
    Require $rejected 'Unreadable/malformed native file must not give a complete pass.'
    Remove-Item -LiteralPath $unknown
    $link = Join-Path $bundle 'linked-directory'
    $target = Join-Path $scratch 'private-outside'; [void](New-Item -ItemType Directory -Path $target)
    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $kind -Path $link -Target $target)
    $rejected = $false
    try { [void](Get-NeuraBundleEvidence $exe) } catch { $rejected = $true }
    Require $rejected 'Links must fail closed instead of traversing outside the bundle.'
    # Delete only the link; never its target, also on Windows PowerShell 5.1.
    [IO.Directory]::Delete($link)

    $now = [datetime]::UtcNow
    $xml = @"
<Event><System><EventID>1000</EventID><TimeCreated SystemTime="$($now.ToString('o'))"/></System><EventData>
<Data Name="AppName">neuro_companion.exe</Data><Data Name="AppPath">$([Security.SecurityElement]::Escape($exe))</Data>
<Data Name="ModuleName">C:\PRIVATE_PERSON_SECRET\sapi.dll</Data><Data Name="ExceptionCode">c0000005</Data>
<Data Name="FaultingOffset">000000000000e657</Data><Data Name="CommandLine">PRIVATE_PERSON_SECRET</Data>
</EventData></Event>
"@
    $event = ConvertTo-NeuraEventEvidence $xml $exe
    Require ($null -ne $event -and $event.module -eq 'sapi.dll') 'Relevant event must preserve only the module basename.'
    Require ($event.association -eq 'PATH_AND_TIME') 'Exact-path association should be recorded.'
    Require ($event.exception_code -eq 'c0000005' -and $event.relative_offset -eq '000000000000e657') 'Exception metadata was lost.'
    Require ((($event | ConvertTo-Json) -notmatch 'PRIVATE_PERSON_SECRET')) 'Raw event paths/command lines must never be exported.'
    Require ($null -eq (ConvertTo-NeuraEventEvidence $xml ($exe + '.other'))) 'Another installed build must not be misattributed.'
    Require ($null -eq (ConvertTo-NeuraEventEvidence ($xml.Replace('neuro_companion.exe', 'other.exe')) $exe)) 'Other applications must be excluded.'
    $werXml = $xml.Replace('<EventID>1000</EventID>', '<EventID>1001</EventID>').Replace('Name="AppName"', 'Name="P1"').Replace('Name="ModuleName"', 'Name="P4"')
    Require ((ConvertTo-NeuraEventEvidence $werXml $exe).event_id -eq 1001) 'Named WER metadata should be accepted.'
    Require ((ConvertTo-NeuraEventEvidence ($xml.Replace('<Event>', '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">')) $exe).event_id -eq 1000) 'Real Windows event XML namespaces must be handled.'
    $module = Get-Module NeuraSpeechEvidence
    & $module { function script:Get-WinEvent { throw 'synthetic access denial' } }
    Require ((Get-NeuraEventEvidence $exe $now.AddMinutes(-1) $now.AddMinutes(1)).status -eq 'UNAVAILABLE') 'Denied event access must not look like an empty successful read.'

    $vault = Join-Path $scratch 'vault'; [void](New-Item -ItemType Directory -Path $vault)
    $records = @(
        @{ ts = $now.ToString('o'); source = 'windows_runner'; type = 'native_breadcrumb'; event = 'primary_first_frame'; secret = 'PRIVATE_PERSON_SECRET' },
        @{ ts = $now.ToString('o'); source = 'windows_runner'; type = 'native_crash'; event = 'unhandled_exception'; exception_code = '0xC0000005'; fault_module = 'flutter_tts_plugin.dll'; fault_address = 'PRIVATE_PERSON_SECRET' },
        @{ ts = $now.AddHours(-6).ToString('o'); source = 'windows_runner'; type = 'native_breadcrumb'; event = 'process_start' },
        @{ ts = $now.ToString('o'); source = 'chat'; type = 'native_breadcrumb'; event = 'primary_first_frame'; text = 'PRIVATE_PERSON_SECRET' },
        @{ ts = $now.ToString('o'); source = 'windows_runner'; type = 'native_breadcrumb'; event = 'PRIVATE_PERSON_SECRET' }
    )
    $lines = @($records | ForEach-Object { $_ | ConvertTo-Json -Compress }); $lines += '{invalid json'
    [IO.File]::WriteAllLines((Join-Path $vault 'neura_error_vault.jsonl'), $lines)
    $result = Get-NeuraNativeEvidence $vault $now.AddMinutes(-1) $now.AddMinutes(1)
    Require ($result.records.Count -eq 2) 'Only current allowlisted native records may be exported.'
    Require ((($result | ConvertTo-Json -Depth 5) -notmatch 'PRIVATE_PERSON_SECRET')) 'Breadcrumb content/raw addresses must not leak.'
    Require ($result.records[1].module -eq 'flutter_tts_plugin.dll') 'Historical fault module evidence must be retained.'
    Require ((Get-NeuraNativeEvidence $target $now.AddMinutes(-1) $now.AddMinutes(1)).status -eq 'NOT_FOUND') 'Missing logs must not be reported as pass.'

    $fakeRoot = Join-Path $scratch 'source'; [void](New-Item -ItemType Directory -Path $fakeRoot)
    $sourcePath = Join-Path $fakeRoot 'synthetic.cpp'
    [IO.File]::WriteAllText($sourcePath, "synthetic`nsource`n")
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestPath = Join-Path $scratch 'manifest.json'
    @{ reference_commit = 'synthetic'; files = @(@{ path = 'synthetic.cpp'; sha256_lf = $sourceHash }) } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Require ((Get-NeuraSourceEvidence $fakeRoot $manifestPath).status -eq 'MATCH') 'Source comparison must match the exact fixture.'
    [IO.File]::WriteAllText($sourcePath, "synthetic`r`nsource`r`n")
    Require ((Get-NeuraSourceEvidence $fakeRoot $manifestPath).status -eq 'MATCH') 'Windows CRLF source must match normalized LF hashes.'
    [IO.File]::WriteAllText($sourcePath, 'changed source')
    Require ((Get-NeuraSourceEvidence $fakeRoot $manifestPath).status -eq 'DIFF_OR_MISSING') 'Changed source must not match.'
    Remove-Item -LiteralPath $sourcePath
    Require ((Get-NeuraSourceEvidence $fakeRoot $manifestPath).status -eq 'DIFF_OR_MISSING') 'Missing source must not silently match.'

    # Exercise report serialization against fixtures, using a test-only copy of
    # the CLI with the platform guard bypassed on Linux. Production stays Windows-only.
    $cliDirectory = Join-Path $scratch 'cli'; [void](New-Item -ItemType Directory -Path $cliDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'NeuraSpeechEvidence.psm1') -Destination $cliDirectory
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'source-reference.json') -Destination $cliDirectory
    $cli = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-NeuraWindowsSpeech.ps1') -Raw
    $cli = $cli.Replace('if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT)', 'if ($false)')
    $cli = $cli.Replace('Get-NeuraEventEvidence $exe.FullName $start $end', '@{ status = ''UNAVAILABLE''; events = @() }')
    $escapedVault = $vault.Replace("'", "''")
    $cli = $cli.Replace('([IO.Path]::GetTempPath()) $start $end', "('$escapedVault') `$start `$end")
    [IO.File]::WriteAllText((Join-Path $cliDirectory 'fixture-cli.ps1'), $cli)
    $shellExe = if ($PSVersionTable.PSEdition -eq 'Core') {
        Join-Path $PSHOME $(if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'pwsh.exe' } else { 'pwsh' })
    } else { Join-Path $PSHOME 'powershell.exe' }
    & $shellExe -NoProfile -File (Join-Path $cliDirectory 'fixture-cli.ps1') -ExePath $exe -OutputParent $cliDirectory
    Require ($LASTEXITCODE -eq 0) 'Fixture CLI report generation failed.'
    $reports = @(Get-ChildItem -LiteralPath $cliDirectory -Directory -Filter 'Neura-Speech-Results-*')
    Require ($reports.Count -eq 1) 'Exactly one new report directory must be created.'
    $json = Get-Content -LiteralPath (Join-Path $reports[0].FullName 'speech-evidence.json') -Raw
    $report = $json | ConvertFrom-Json
    Require ($report.bundle_unchanged) 'Unchanged bundle identity should be retained.'
    Require (@($report.physical_results | Where-Object { $_.status -ne 'NOT RUN' }).Count -eq 0) 'Inspect-only run must never invent physical results.'
    Require ($report.acceptance -eq 'PENDING_PHYSICAL_WINDOWS_EVIDENCE') 'Helper must not close acceptance automatically.'
    Require ($json -notmatch 'PRIVATE_PERSON_SECRET|private-outside') 'End-to-end report leaked fixture private data.'
    # Simulated keyboard answers exercise labeling and minimum repetition gates;
    # they are never exported as real observations and are deleted below.
    @('YES', 'R', 'H', 'P', '1', 'F', '1') | & $shellExe -NoProfile -File (Join-Path $cliDirectory 'fixture-cli.ps1') -ExePath $exe -OutputParent $cliDirectory -Observe
    Require ($LASTEXITCODE -eq 0) 'Simulated observation CLI failed.'
    $reports = @(Get-ChildItem -LiteralPath $cliDirectory -Directory -Filter 'Neura-Speech-Results-*' | Sort-Object CreationTimeUtc -Descending)
    $report = Get-Content -LiteralPath (Join-Path $reports[0].FullName 'speech-evidence.json') -Raw | ConvertFrom-Json
    Require ($report.physical_results[0].status -eq 'PARTIAL') 'Too few repetitions must not count as pass.'
    Require ($report.physical_results[1].status -eq 'FAIL') 'Reported failure must be retained.'
    Require ($report.physical_results[2].status -eq 'NOT RUN') 'Observed failure must stop subsequent tests.'
    Require ($report.physical_results[0].observation_source -eq 'OPERATOR_REPORT_NOT_AUTOMATICALLY_VERIFIED') 'Operator reports must not masquerade as measured audio.'
    Write-Host "$script:checks synthetic helper assertions passed; no speech or physical Windows acceptance executed."
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
