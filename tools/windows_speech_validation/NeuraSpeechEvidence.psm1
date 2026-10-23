#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Read-only helpers. No application launch, COM voice, registry, network,
# microphone, preference writes, raw-log export or automatic acceptance.
function Get-NeuraPlainItem([string]$Path) {
    if ($Path -match '^(\\\\|//)' -or $Path -match '^[a-z]+://') {
        throw 'Use a plain local filesystem path.'
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem') { throw 'Use a filesystem path.' }
    $cursor = $item
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Linked files and directories are not accepted.'
        }
        $cursor = if ($cursor -is [IO.DirectoryInfo]) { $cursor.Parent } else { $cursor.Directory }
    }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($item.FullName))
    if ($drive.DriveType -eq [IO.DriveType]::Network) { throw 'Network drives are not accepted.' }
    return $item
}

function Get-NeuraModuleLabel([string]$Name) {
    $leaf = ($Name -split '[\\/]')[-1].ToLowerInvariant()
    if ($leaf -in @('neuro_companion.exe', 'flutter_windows.dll', 'flutter_tts_plugin.dll',
        'sapi.dll', 'ntdll.dll', 'kernelbase.dll', 'kernel32.dll', 'ucrtbase.dll',
        'combase.dll', 'ole32.dll', 'neura_swarm.dll', 'app.so')) { return $leaf }
    return 'other_module'
}

function Get-NeuraBinaryEvidence([string]$Path, [switch]$RequireSapi) {
    $item = Get-NeuraPlainItem $Path
    if ($item.PSIsContainer -or $item.Length -lt 64 -or $item.Length -gt 256MB) {
        throw 'Native binary is missing, malformed or exceeds the inspection bound.'
    }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    # Latin-1 provides a reversible byte-to-character mapping on both .NET versions.
    $encoding = [Text.Encoding]::GetEncoding(28591)
    $text = $encoding.GetString($bytes)
    $pe = [BitConverter]::ToInt32($bytes, 60)
    $validPe = $bytes[0] -eq 0x4d -and $bytes[1] -eq 0x5a -and
        $pe -ge 64 -and $pe -le ($bytes.Length - 24)
    $machine = 0
    if ($validPe) {
        $validPe = [BitConverter]::ToUInt32($bytes, $pe) -eq 0x4550
        if ($validPe) { $machine = [BitConverter]::ToUInt16($bytes, $pe + 4) }
    }
    $legacy = $text.IndexOf('FlutterTtsPlugin', [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $text.IndexOf('flutter_tts_plugin.dll', [StringComparison]::OrdinalIgnoreCase) -ge 0
    $markers = [ordered]@{}
    if ($RequireSapi) {
        foreach ($marker in @('neura/speech_synthesis', 'local_speech_unavailable',
            'No local desktop voice installed', 'Local speech requires an application restart.')) {
            $markers[$marker] = $text.Contains($marker)
        }
        foreach ($marker in @('Vendor=Microsoft', 'TTS_MS_')) {
            $markers[$marker] = $text.Contains($encoding.GetString([Text.Encoding]::Unicode.GetBytes($marker)))
        }
        $markers['CLSID_SpVoice'] = $text.Contains($encoding.GetString(
            ([Guid]'96749377-3391-11d2-9ee3-00c04f797396').ToByteArray()))
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $hash = -join ($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) }
    finally { $algorithm.Dispose() }
    return [pscustomobject]@{
        sha256 = $hash; size_bytes = $bytes.Length; valid_pe = $validPe
        machine = ('0x{0:x4}' -f $machine); legacy_indicators = $legacy
        sapi_markers = $markers
        # Static fingerprint only: not proof of execution, commit or source-line behavior.
        static_sapi_match = $RequireSapi.IsPresent -and $validPe -and $machine -eq 0x8664 -and
            -not (@($markers.Values) -contains $false) -and -not $legacy
    }
}

function Get-NeuraBundleEvidence([string]$ExePath) {
    $exe = Get-NeuraPlainItem $ExePath
    if ($exe.Name -ine 'neuro_companion.exe' -or $exe.PSIsContainer) {
        throw 'Select the installed neuro_companion.exe, not a launcher or source folder.'
    }
    $binary = Get-NeuraBinaryEvidence $exe.FullName -RequireSapi
    $files = [Collections.Generic.List[object]]::new()
    $queue = [Collections.Generic.Queue[IO.DirectoryInfo]]::new()
    $queue.Enqueue($exe.Directory)
    $legacyFile = $false
    $legacyIndicator = $binary.legacy_indicators
    $visited = 0
    $nativeCount = 0
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($child in Get-ChildItem -LiteralPath $directory.FullName -Force) {
            $visited++
            if ($visited -gt 15000) { throw 'Bundle exceeds the inspection bound.' }
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Bundle contains a link; inspection cannot establish completeness.'
            }
            if ($child.PSIsContainer) { $queue.Enqueue($child); continue }
            if ($child.Name -ieq 'flutter_tts_plugin.dll') { $legacyFile = $true }
            if ($child.Extension -notin @('.exe', '.dll', '.pdb') -and
                $child.FullName -notin @((Join-Path $exe.DirectoryName 'data/app.so'),
                    (Join-Path $exe.DirectoryName 'data/flutter_assets/kernel_blob.bin'))) { continue }
            $nativeCount++
            if ($nativeCount -gt 256 -or $child.Length -gt 256MB) {
                throw 'Native files exceed the inspection bound.'
            }
            # File paths/names outside a small public allowlist never enter the report.
            $label = Get-NeuraModuleLabel $child.Name
            if ($label -eq 'other_module') { $label = 'additional_file_{0:d3}' -f $nativeCount }
            if ($child.Extension -in @('.exe', '.dll')) {
                $info = Get-NeuraBinaryEvidence $child.FullName
                if (-not $info.valid_pe) { throw 'A native executable or DLL is not a valid PE file.' }
                $legacyIndicator = $legacyIndicator -or $info.legacy_indicators
                $hash = $info.sha256
            } else {
                $hash = (Get-FileHash -LiteralPath $child.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            $files.Add([pscustomobject]@{ label = $label; size_bytes = $child.Length; sha256 = $hash })
        }
    }
    $enginePresent = Test-Path -LiteralPath (Join-Path $exe.DirectoryName 'flutter_windows.dll') -PathType Leaf
    $dataPresent = Test-Path -LiteralPath (Join-Path $exe.DirectoryName 'data/icudtl.dat') -PathType Leaf
    return [pscustomobject]@{
        status = $(if ($binary.static_sapi_match -and -not $legacyFile -and -not $legacyIndicator -and
            $enginePresent -and $dataPresent) { 'PASS' } else { 'FAIL' })
        scope = 'Static bundle fingerprint; no runtime or provenance acceptance'
        executable = $binary; legacy_dll_bundled = $legacyFile
        legacy_registration_or_import_indicators = $legacyIndicator
        flutter_engine_present = $enginePresent; flutter_data_present = $dataPresent
        native_files = @($files.ToArray()); commit_provenance = 'UNVERIFIED'
    }
}

function Get-NeuraSourceEvidence([string]$SourceRoot, [string]$ManifestPath) {
    if ([string]::IsNullOrWhiteSpace($SourceRoot)) { return @{ status = 'NOT_PROVIDED' } }
    $root = Get-NeuraPlainItem $SourceRoot
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $mismatches = @()
    foreach ($entry in $manifest.files) {
        # The shipped manifest is fixed data, nevertheless reject traversal.
        if ($entry.path -notmatch '^[a-zA-Z0-9_./-]+$' -or $entry.path -match '(^|/)\.\.(/|$)') {
            throw 'Invalid source manifest.'
        }
        try {
            $item = Get-NeuraPlainItem (Join-Path $root.FullName $entry.path)
            if ($item.PSIsContainer -or $item.Length -gt 1MB) { throw 'Source exceeds the comparison bound.' }
            $normalized = [IO.File]::ReadAllText($item.FullName).Replace("`r`n", "`n")
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try { $hash = -join ($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)) |
                ForEach-Object { $_.ToString('x2') }) } finally { $algorithm.Dispose() }
            if ($hash -ne $entry.sha256_lf) { $mismatches += $entry.path }
        } catch { $mismatches += $entry.path }
    }
    return @{
        status = $(if ($mismatches.Count -eq 0) { 'MATCH' } else { 'DIFF_OR_MISSING' })
        reference_commit = $manifest.reference_commit; mismatched_source_files = @($mismatches)
        scope = 'Normalized source comparison only; does not bind the executable to this source'
    }
}

function ConvertTo-NeuraEventEvidence([string]$Xml, [string]$ExePath) {
    if ($Xml.Length -gt 1MB) { throw 'Event XML exceeds the inspection bound.' }
    $document = [xml]::new()
    $document.XmlResolver = $null
    $document.LoadXml($Xml)
    $eventId = [int]$document.GetElementsByTagName('EventID')[0].InnerText
    if ($eventId -notin @(1000, 1001, 1002)) { return }
    $fields = @{}
    foreach ($node in @($document.GetElementsByTagName('Data'))) {
        if ($node.HasAttribute('Name')) { $fields[$node.GetAttribute('Name')] = $node.InnerText }
    }
    $app = if ($fields.ContainsKey('AppName')) { $fields['AppName'] } else { $fields['P1'] }
    if ($app -ine 'neuro_companion.exe') { return }
    $association = 'NAME_AND_TIME_ONLY'
    if ($fields.ContainsKey('AppPath')) {
        if (-not [string]::Equals($fields['AppPath'], $ExePath, [StringComparison]::OrdinalIgnoreCase)) { return }
        $association = 'PATH_AND_TIME'
    }
    $code = ''
    foreach ($key in @('ExceptionCode', 'P7')) {
        if ($fields.ContainsKey($key) -and $fields[$key] -match '^(?:0x)?[0-9a-fA-F]{8}$') { $code = $fields[$key] }
    }
    $module = if ($fields.ContainsKey('ModuleName')) { $fields['ModuleName'] } else { $fields['P4'] }
    $offset = ''
    if ($fields.ContainsKey('FaultingOffset') -and $fields['FaultingOffset'] -match '^(?:0x)?[0-9a-fA-F]{1,16}$') {
        $offset = $fields['FaultingOffset']
    }
    return [pscustomobject]@{
        event_id = $eventId; utc = ([datetimeoffset]$document.GetElementsByTagName('TimeCreated')[0].GetAttribute('SystemTime')).ToUniversalTime().ToString('o')
        association = $association; exception_code = $code
        module = Get-NeuraModuleLabel ([string]$module); relative_offset = $offset
    }
}

function Get-NeuraEventEvidence([string]$ExePath, [datetime]$StartUtc, [datetime]$EndUtc) {
    try {
        $records = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = @(1000, 1001, 1002)
            StartTime = $StartUtc; EndTime = $EndUtc } -MaxEvents 512 -ErrorAction Stop)
        $filtered = @(foreach ($record in $records) {
            try { ConvertTo-NeuraEventEvidence $record.ToXml() $ExePath } catch { }
        })
        return @{ status = $(if ($records.Count -ge 512) { 'TRUNCATED' } else { 'READ' }); events = $filtered }
    } catch {
        # Get-WinEvent uses this exact error ID when the query has no matches.
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return @{ status = 'NONE_OBSERVED'; events = @() } }
        return @{ status = 'UNAVAILABLE'; events = @() }
    }
}

function Get-NeuraNativeEvidence([string]$VaultDirectory, [datetime]$StartUtc, [datetime]$EndUtc) {
    $allowedEvents = @('process_start', 'flutter_controller_create_failed', 'flutter_controller_created',
        'window_role_channel_registered', 'plugins_registered', 'native_channels_registered',
        'mascot_first_frame', 'primary_first_frame', 'unhandled_exception', 'cpp_terminate')
    $events = [Collections.Generic.List[object]]::new()
    $read = 0
    $status = 'NOT_FOUND'
    foreach ($suffix in @('', '.1', '.2', '.3')) {
        $path = Join-Path $VaultDirectory ('neura_error_vault.jsonl' + $suffix)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $item = Get-NeuraPlainItem $path
            if ($item.Length -gt 1MB -or $read + $item.Length -gt 4MB) { $status = 'INCOMPLETE'; continue }
            $read += $item.Length
            $reader = [IO.StreamReader]::new($item.FullName)
            try {
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ($line.Length -gt 8192) { continue }
                    try {
                        $entry = $line | ConvertFrom-Json
                        if ($entry.source -ne 'windows_runner' -or $entry.type -notin @('native_crash', 'native_breadcrumb') -or
                            $entry.event -notin $allowedEvents) { continue }
                        $utc = ([datetimeoffset]$entry.ts).UtcDateTime
                        if ($utc -lt $StartUtc -or $utc -gt $EndUtc) { continue }
                        $clean = [ordered]@{ utc = $utc.ToString('o'); type = $entry.type
                            event = $entry.event; association = 'TIME_ONLY_NOT_BINARY_BOUND' }
                        if ($entry.type -eq 'native_crash' -and $entry.event -eq 'unhandled_exception') {
                            $clean['module'] = Get-NeuraModuleLabel ([string]$entry.fault_module)
                            if ($entry.exception_code -match '^0x[0-9a-fA-F]{8}$') { $clean['exception_code'] = $entry.exception_code }
                        }
                        $events.Add([pscustomobject]$clean)
                    } catch { } # malformed/unrelated records are never copied
                }
            } finally { $reader.Dispose() }
            if ($status -ne 'INCOMPLETE') { $status = 'READ' }
        } catch { $status = 'INCOMPLETE' }
    }
    return @{ status = $status; records = @($events.ToArray()) }
}

Export-ModuleMember -Function Get-NeuraPlainItem, Get-NeuraModuleLabel, Get-NeuraBinaryEvidence,
    Get-NeuraBundleEvidence, Get-NeuraSourceEvidence, ConvertTo-NeuraEventEvidence,
    Get-NeuraEventEvidence, Get-NeuraNativeEvidence
