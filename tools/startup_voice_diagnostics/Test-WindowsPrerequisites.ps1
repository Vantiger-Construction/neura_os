#Requires -Version 5.1
<#
.SYNOPSIS
Read-only startup-voice prerequisites. Never creates a recognizer or voice.
.DESCRIPTION
Enumerates the same Microsoft desktop token categories as the native owners.
Writes only a new report. No speech, mic activation, app launch, registry write,
permission change, download, data access or upload is performed.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Run this prerequisite collector on Windows; device acceptance remains NOT RUN.'
}
if (Test-Path -LiteralPath $OutputFile) { throw 'Choose a new output filename.' }
if (-not [Environment]::Is64BitProcess) {
    throw 'Use 64-bit Windows PowerShell so the token view matches the x64 application.'
}

function Get-DesktopTokens([string]$CategoryName, [string]$Pattern) {
    $category = $null
    $tokens = $null
    $rows = @()
    try {
        $category = New-Object -ComObject SAPI.SpObjectTokenCategory
        $category.SetId(('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\' + $CategoryName), $false)
        $tokens = $category.EnumerateTokens('Vendor=Microsoft', '')
        for ($i = 0; $i -lt [Math]::Min(128, $tokens.Count); $i++) {
            $token = $null
            try {
                $token = $tokens.Item($i)
                $leaf = ($token.Id -split '\\')[-1]
                if ($leaf -cnotmatch $Pattern) { continue }
                if ($leaf -notmatch '^[A-Za-z0-9_-]{1,160}$') { continue }
                $language = 'UNKNOWN'
                try {
                    $value = $token.GetAttribute('Language')
                    if ($value -match '^[A-Fa-f0-9;]{1,64}$') { $language = $value }
                } catch { }
                $rows += [ordered]@{ token = $leaf; language_hex = $language }
            } finally {
                if ($null -ne $token) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($token) }
            }
        }
        return [ordered]@{ collection = 'AVAILABLE'; eligible_count = $rows.Count; tokens = $rows }
    } catch {
        return [ordered]@{ collection = 'BLOCKED'; eligible_count = 0; tokens = @()
            reason = 'Desktop SAPI catalog unavailable; no raw COM error exported' }
    } finally {
        if ($null -ne $tokens) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($tokens) }
        if ($null -ne $category) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($category) }
    }
}

function Get-MicPrivacyValue([string]$Path) {
    try {
        $value = (Get-ItemProperty -LiteralPath $Path -Name Value -ErrorAction Stop).Value
        if ($value -in @('Allow', 'Deny')) { return $value }
        return 'UNKNOWN'
    } catch { return 'UNAVAILABLE' }
}

$recognizers = Get-DesktopTokens 'Recognizers' '^MS-.*-DESK'
$voices = Get-DesktopTokens 'Voices' '^TTS_MS_'
$base = 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
$report = [ordered]@{
    schema = 1; created_utc = [datetime]::UtcNow.ToString('o')
    scope = 'READ_ONLY_PREREQUISITE_INVENTORY'
    os_version = [Environment]::OSVersion.Version.ToString()
    powershell_version = $PSVersionTable.PSVersion.ToString(); process_bits = 64
    recognizers = $recognizers; output_voices = $voices
    microphone_privacy = [ordered]@{
        machine = Get-MicPrivacyValue ('Registry::HKEY_LOCAL_MACHINE\' + $base)
        current_user = Get-MicPrivacyValue ('Registry::HKEY_CURRENT_USER\' + $base)
        desktop_apps = Get-MicPrivacyValue ('Registry::HKEY_CURRENT_USER\' + $base + '\NonPackaged')
        limit = 'Registry values are advisory; verify Windows Privacy and security > Microphone and desktop app access manually'
    }
    prerequisite_status = $(if ($recognizers.collection -ne 'AVAILABLE' -or $voices.collection -ne 'AVAILABLE' -or
        $recognizers.eligible_count -eq 0 -or $voices.eligible_count -eq 0) { 'BLOCKED' } else { 'PASS' })
    hardware_acceptance = 'NOT RUN'
    microphone_and_audio_devices = 'NOT OPENED; check input/output selection manually'
    privacy = 'No recognizer, voice, microphone or Neura process instantiated; no usernames, machine names, full paths or app data saved'
}
$full = [IO.Path]::GetFullPath($OutputFile)
$parent = [IO.Path]::GetDirectoryName($full)
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Create the report directory first.' }
$json = $report | ConvertTo-Json -Depth 8
$stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json + [Environment]::NewLine)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Host 'Prerequisite inventory saved. PASS means eligible tokens were found, not hardware acceptance.'
if ($report.prerequisite_status -eq 'BLOCKED') { exit 2 }
exit 0
