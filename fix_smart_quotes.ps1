#Requires -Version 5.1
<#
  Backward-compatible entry point for Neura Dart repair.

  Existing commands that call .\fix_smart_quotes.ps1 continue to work, while
  the implementation now lives in the hardened, backup-aware repair tool at:

    tools\neura_dart_repair\tools\Neura-DartRepair.ps1

  Examples:
    .\fix_smart_quotes.ps1
    .\fix_smart_quotes.ps1 -DryRun
    .\fix_smart_quotes.ps1 -Root .\lib -RunAnalyzer -AutoFixStringLiterals
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DryRun,
    [switch]$RunAnalyzer,
    [switch]$AutoFixStringLiterals,
    [switch]$RestoreLatestBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tool = Join-Path $PSScriptRoot 'tools\neura_dart_repair\tools\Neura-DartRepair.ps1'
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    throw "Hardened Neura repair tool not found: $tool"
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Get-Location).Path
}

$resolved = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
if ((Split-Path -Leaf $resolved) -ieq 'lib') {
    $parent = Split-Path -Parent $resolved
    if (Test-Path -LiteralPath (Join-Path $parent 'pubspec.yaml') -PathType Leaf) {
        $resolved = $parent
    }
}

$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-Root', $resolved)
if ($DryRun) { $arguments += '-WhatIf' }
if ($RunAnalyzer) { $arguments += '-RunAnalyzer' }
if ($AutoFixStringLiterals) { $arguments += '-AutoFixStringLiterals' }
if ($RestoreLatestBackup) { $arguments += '-RestoreLatestBackup' }

& powershell.exe @arguments
exit $LASTEXITCODE
