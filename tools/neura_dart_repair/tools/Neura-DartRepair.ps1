#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Root,
    [switch]$RunAnalyzer,
    [switch]$AutoFixStringLiterals,
    [switch]$NoBackup,
    [switch]$IncludeTest,
    [ValidateRange(1, 5)][int]$MaxPasses = 2,
    [string]$ReportDirectory,
    [switch]$RestoreLatestBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    Write-Host $Message -ForegroundColor $Color
}

function Test-FlutterRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'pubspec.yaml') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $Path 'lib') -PathType Container)
}

function Find-FlutterRoot([string]$RequestedRoot) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($RequestedRoot) { $candidates.Add($RequestedRoot) }
    $candidates.Add((Get-Location).Path)
    $candidates.Add($PSScriptRoot)
    $candidates.Add((Split-Path -Parent $PSScriptRoot))
    $candidates.Add('D:\Vantiger1\neura_os')
    $candidates.Add('D:\neura_os')
    $candidates.Add('C:\neura_os')

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        try {
            $resolved = [System.IO.Path]::GetFullPath($candidate)
            $cursor = $resolved
            for ($i = 0; $i -lt 8 -and $cursor; $i++) {
                if (Test-FlutterRoot $cursor) { return (Resolve-Path -LiteralPath $cursor).Path }
                $parent = Split-Path -Parent $cursor
                if ($parent -eq $cursor) { break }
                $cursor = $parent
            }
        } catch { }
    }

    # Bounded child search only; never crawl an entire drive.
    foreach ($base in @((Get-Location).Path, (Split-Path -Parent $PSScriptRoot), 'D:\Vantiger1', 'D:\')) {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        try {
            $matches = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    if (Test-FlutterRoot $_.FullName) { $_.FullName }
                    Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue |
                        Where-Object { Test-FlutterRoot $_.FullName } |
                        ForEach-Object FullName
                } | Select-Object -Unique
            if (@($matches).Count -eq 1) { return @($matches)[0] }
        } catch { }
    }

    throw "Flutter project root not found. Pass -Root 'D:\path\to\neura_os'. The root must contain pubspec.yaml and lib\."
}

function Get-RelativePath([string]$BasePath, [string]$TargetPath) {
    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', '\')
}

function Get-TextEncodingInfo([byte[]]$Bytes) {
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return @{ Encoding = New-Object System.Text.UTF8Encoding($true); HasBom = $true }
    }
    return @{ Encoding = New-Object System.Text.UTF8Encoding($false, $true); HasBom = $false }
}

function Read-Utf8File([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    try {
        $info = Get-TextEncodingInfo $bytes
        return @{ Text = $info.Encoding.GetString($bytes); HasBom = $info.HasBom }
    } catch {
        throw "File is not valid UTF-8 and was not modified: $Path"
    }
}

function Write-Utf8File([string]$Path, [string]$Text, [bool]$HasBom) {
    $encoding = New-Object System.Text.UTF8Encoding($HasBom)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function New-Backup([string]$ProjectRoot, [string]$Label) {
    $folder = Join-Path $ProjectRoot ('.neura_repair\backups\{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $Label)
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    return $folder
}

function Backup-File([string]$Path, [string]$ProjectRoot, [string]$BackupRoot) {
    $relative = Get-RelativePath $ProjectRoot $Path
    $destination = Join-Path $BackupRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    return $relative
}

function Restore-Backup([string]$BackupRoot, [string]$ProjectRoot) {
    if (-not (Test-Path -LiteralPath $BackupRoot)) { throw "Backup not found: $BackupRoot" }
    Get-ChildItem -LiteralPath $BackupRoot -File -Recurse | Where-Object Name -ne 'manifest.json' | ForEach-Object {
        $relative = Get-RelativePath $BackupRoot $_.FullName
        $destination = Join-Path $ProjectRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
}

function Invoke-Analyzer([string]$ProjectRoot, [string]$OutputPath) {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    $dart = Get-Command dart -ErrorAction SilentlyContinue
    Push-Location $ProjectRoot
    try {
        if ($dart) {
            $output = & $dart.Source analyze --format machine 2>&1 | ForEach-Object { $_.ToString() }
            $exitCode = $LASTEXITCODE
        } elseif ($flutter) {
            $output = & $flutter.Source analyze --no-pub 2>&1 | ForEach-Object { $_.ToString() }
            $exitCode = $LASTEXITCODE
        } else {
            throw 'Neither dart nor flutter is available on PATH.'
        }
    } finally {
        Pop-Location
    }
    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    # Count only analyzer severity lines. Do not count words such as "error"
    # that happen to occur inside warning/info messages or summaries.
    $errors = @($output | Where-Object {
        $_ -match '^ERROR\|' -or $_ -match '(?i)^\s*error\s*(?:-|•|:)'
    }).Count
    return @{ ExitCode = $exitCode; ErrorCount = $errors; Lines = @($output) }
}

function Get-Diagnostics([string[]]$AnalyzerLines, [string]$ProjectRoot) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in $AnalyzerLines) {
        # dart analyze --format machine
        if ($line -match '^(?<sev>ERROR|WARNING|INFO)\|[^|]*\|(?<code>[^|]*)\|(?<file>[^|]+)\|(?<line>\d+)\|(?<col>\d+)\|') {
            $items.Add([pscustomobject]@{ Severity=$Matches.sev; Code=$Matches.code; File=$Matches.file; Line=[int]$Matches.line; Column=[int]$Matches.col })
            continue
        }
        # flutter analyze human-readable output
        if ($line -match '(?i)(?<file>(?:[A-Za-z]:)?[^\r\n:]+\.dart):(?<line>\d+):(?<col>\d+).*(?<code>unterminated_string_literal|expected_token|missing_quote)') {
            $file = $Matches.file.Trim()
            if (-not [System.IO.Path]::IsPathRooted($file)) { $file = Join-Path $ProjectRoot $file }
            $items.Add([pscustomobject]@{ Severity='ERROR'; Code=$Matches.code; File=$file; Line=[int]$Matches.line; Column=[int]$Matches.col })
        }
    }
    return @($items)
}

function Get-UnescapedPositions([string]$Text, [char]$Quote) {
    $positions = New-Object System.Collections.Generic.List[int]
    for ($i=0; $i -lt $Text.Length; $i++) {
        if ($Text[$i] -ne $Quote) { continue }
        $slashes = 0
        for ($j=$i-1; $j -ge 0 -and $Text[$j] -eq '\'; $j--) { $slashes++ }
        if (($slashes % 2) -eq 0) { $positions.Add($i) }
    }
    return @($positions)
}

function Try-RepairDiagnosticLine([string]$LineText) {
    # Conservative repair: only switch delimiters when the analyzer points at a line
    # with exactly three unescaped matching quotes and the middle quote is an apostrophe
    # between letters/digits. This targets strings such as 'don't' after smart-quote cleanup.
    foreach ($quote in @("'", '"')) {
        $positions = @(Get-UnescapedPositions $LineText ([char]$quote))
        if ($positions.Count -ne 3) { continue }
        $other = if ($quote -eq "'") { '"' } else { "'" }
        if ((Get-UnescapedPositions $LineText ([char]$other)).Count -gt 0) { continue }
        $middle = $positions[1]
        if ($middle -le 0 -or $middle -ge ($LineText.Length - 1)) { continue }
        if ($LineText[$middle-1] -notmatch '[A-Za-z0-9]' -or $LineText[$middle+1] -notmatch '[A-Za-z0-9]') { continue }

        $chars = $LineText.ToCharArray()
        $chars[$positions[0]] = [char]$other
        $chars[$positions[2]] = [char]$other
        return -join $chars
    }
    return $null
}

$projectRoot = Find-FlutterRoot $Root
$repairRoot = Join-Path $projectRoot '.neura_repair'
if (-not $ReportDirectory) { $ReportDirectory = Join-Path $repairRoot 'reports' }
New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportPath = Join-Path $ReportDirectory ("repair_$runId.json")

if ($RestoreLatestBackup) {
    $latest = Get-ChildItem -LiteralPath (Join-Path $repairRoot 'backups') -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No Neura repair backup was found.' }
    Restore-Backup $latest.FullName $projectRoot
    Write-Status "Restored backup: $($latest.FullName)" Green
    exit 0
}

Write-Status 'Neura Dart Repair' Cyan
Write-Status "Project root: $projectRoot" Cyan

$scanRoots = @((Join-Path $projectRoot 'lib'))
if ($IncludeTest -and (Test-Path -LiteralPath (Join-Path $projectRoot 'test'))) { $scanRoots += (Join-Path $projectRoot 'test') }
$files = @($scanRoots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Filter '*.dart' })
if ($files.Count -eq 0) { throw 'No Dart files were found under lib (or test).' }

$replacements = [ordered]@{
    ([string][char]0x2018) = "'"; ([string][char]0x2019) = "'"; ([string][char]0x201A) = "'"; ([string][char]0x2032) = "'"
    ([string][char]0x201C) = '"'; ([string][char]0x201D) = '"'; ([string][char]0x201E) = '"'; ([string][char]0x2033) = '"'
    ([string][char]0x00A0) = ' '; ([string][char]0x200B) = ''; ([string][char]0x2060) = ''; ([string][char]0xFEFF) = ''
}

$changedFiles = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$backupRoot = $null
if (-not $NoBackup -and -not $WhatIfPreference) { $backupRoot = New-Backup $projectRoot 'normalize' }

foreach ($file in $files) {
    try { $read = Read-Utf8File $file.FullName } catch { $warnings.Add($_.Exception.Message); continue }
    $text = $read.Text
    $original = $text
    foreach ($key in $replacements.Keys) { $text = $text.Replace($key, $replacements[$key]) }
    if ($text -eq $original) { continue }
    $relative = Get-RelativePath $projectRoot $file.FullName
    if ($PSCmdlet.ShouldProcess($relative, 'Normalize typographic quotes and invisible Unicode characters')) {
        if ($backupRoot) { [void](Backup-File $file.FullName $projectRoot $backupRoot) }
        Write-Utf8File $file.FullName $text $read.HasBom
        $changedFiles.Add($relative)
        Write-Status "fixed: $relative" Green
    }
}

$baseline = $null
$finalAnalyzer = $null
$autoFixed = New-Object System.Collections.Generic.List[string]
if ($RunAnalyzer -or $AutoFixStringLiterals) {
    $baselinePath = Join-Path $ReportDirectory ("analyze_before_$runId.txt")
    $baseline = Invoke-Analyzer $projectRoot $baselinePath
    Write-Status "Analyzer errors after normalization: $($baseline.ErrorCount)" Yellow
}

if ($AutoFixStringLiterals -and -not $WhatIfPreference) {
    for ($pass=1; $pass -le $MaxPasses; $pass++) {
        $diagnostics = @(Get-Diagnostics $baseline.Lines $projectRoot | Where-Object { $_.Code -match '(?i)unterminated_string_literal|missing_quote' })
        if ($diagnostics.Count -eq 0) { break }
        $passBackup = if ($NoBackup) { $null } else { New-Backup $projectRoot ("strings_pass$pass") }
        $passChanged = New-Object System.Collections.Generic.List[string]

        foreach ($group in ($diagnostics | Group-Object File)) {
            $path = $group.Name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $read = Read-Utf8File $path
            $newline = if ($read.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
            $endsWithNewline = $read.Text.EndsWith("`n")
            $lines = $read.Text -split "`r?`n"
            $modified = $false
            foreach ($diag in ($group.Group | Sort-Object Line -Unique)) {
                $index = $diag.Line - 1
                if ($index -lt 0 -or $index -ge $lines.Count) { continue }
                $candidate = Try-RepairDiagnosticLine $lines[$index]
                if ($null -ne $candidate -and $candidate -ne $lines[$index]) {
                    $lines[$index] = $candidate
                    $modified = $true
                }
            }
            if ($modified) {
                if ($passBackup) { [void](Backup-File $path $projectRoot $passBackup) }
                $newText = ($lines -join $newline)
                if ($endsWithNewline -and -not $newText.EndsWith($newline)) { $newText += $newline }
                Write-Utf8File $path $newText $read.HasBom
                $relative = Get-RelativePath $projectRoot $path
                $passChanged.Add($relative)
            }
        }

        if ($passChanged.Count -eq 0) { break }
        $afterPath = Join-Path $ReportDirectory ("analyze_after_pass${pass}_$runId.txt")
        $after = Invoke-Analyzer $projectRoot $afterPath
        if ($after.ErrorCount -gt $baseline.ErrorCount) {
            if ($passBackup) { Restore-Backup $passBackup $projectRoot }
            $warnings.Add("Auto-fix pass $pass was rolled back because analyzer errors increased from $($baseline.ErrorCount) to $($after.ErrorCount).")
            break
        }
        foreach ($item in $passChanged) { $autoFixed.Add($item) }
        $baseline = $after
        Write-Status "Auto-fix pass $pass: analyzer errors = $($after.ErrorCount)" Yellow
    }
    $finalAnalyzer = $baseline
} elseif ($baseline) {
    $finalAnalyzer = $baseline
}

$report = [ordered]@{
    toolVersion = '1.0.0'
    timestamp = (Get-Date).ToString('o')
    projectRoot = $projectRoot
    whatIf = [bool]$WhatIfPreference
    normalizedFiles = @($changedFiles)
    autoFixedStringFiles = @($autoFixed | Select-Object -Unique)
    backup = $backupRoot
    analyzerExitCode = if ($finalAnalyzer) { $finalAnalyzer.ExitCode } else { $null }
    analyzerErrorCount = if ($finalAnalyzer) { $finalAnalyzer.ErrorCount } else { $null }
    warnings = @($warnings)
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Status "Files normalized: $($changedFiles.Count)" Cyan
Write-Status "Files auto-fixed: $(@($autoFixed | Select-Object -Unique).Count)" Cyan
if ($backupRoot) { Write-Status "Backup: $backupRoot" Cyan }
Write-Status "Report: $reportPath" Cyan
foreach ($warning in $warnings) { Write-Status "WARNING: $warning" Yellow }
if ($finalAnalyzer -and $finalAnalyzer.ErrorCount -gt 0) {
    Write-Status 'Analyzer still reports errors. Review the analyzer report; no speculative broad edits were made.' Yellow
    exit 1
}
exit 0
