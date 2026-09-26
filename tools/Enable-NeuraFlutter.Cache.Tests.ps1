#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exercise cache changes with temporary fixtures, without downloading an SDK
# or accessing the runner's retained tool cache.
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $PSScriptRoot 'Enable-NeuraFlutter.ps1'),
  [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw "Flutter installer syntax errors: $parseErrors" }
foreach ($name in @(
  'Test-NeuraFlutterSdk', 'Get-NeuraFlutterArchive',
  'Assert-NeuraFlutterInstallSpace', 'Get-NeuraFlutterExpandedBytes',
  'Install-NeuraFlutterStagedSdk'
)) {
  $definition = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -eq $name
  }, $true)
  if ($null -eq $definition) { throw "Missing installer function: $name" }
  . ([scriptblock]::Create($definition.Extent.Text))
}

function New-TestFlutterSdk {
  param([string]$Root, [switch]$Unhealthy, [switch]$FailAfterMove)
  $bin = Join-Path $Root 'bin'
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  $executable = Join-Path $bin 'flutter.bat'
  $exitCode = if ($Unhealthy) { 1 } else { 0 }
  if ($env:OS -eq 'Windows_NT') {
    $lines = @('@echo off')
    if ($FailAfterMove) {
      $lines += @(
        'if exist "%NEURA_TEST_FLUTTER_PROBE_MARKER%" exit /b 1',
        'type nul > "%NEURA_TEST_FLUTTER_PROBE_MARKER%"'
      )
    }
    $lines += @('echo Flutter 3.47.5 - stable', "exit /b $exitCode")
  } else {
    $lines = @('#!/bin/sh')
    if ($FailAfterMove) {
      $lines += @(
        '[ ! -f "$NEURA_TEST_FLUTTER_PROBE_MARKER" ] || exit 1',
        ': > "$NEURA_TEST_FLUTTER_PROBE_MARKER"'
      )
    }
    $lines += @('echo "Flutter 3.47.5 - stable"', "exit $exitCode")
  }
  $lines | Set-Content -LiteralPath $executable -Encoding Ascii
  if ($env:OS -ne 'Windows_NT') { & chmod +x $executable }
}

function Assert-TestThrows {
  param([scriptblock]$Action, [string]$MessagePattern)
  $caught = $null
  try { & $Action } catch { $caught = $_ }
  if ($null -eq $caught -or $caught.Exception.Message -notmatch $MessagePattern) {
    throw "Expected failure matching '$MessagePattern', got '$caught'."
  }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) (
  'neura flutter cache ' + [guid]::NewGuid().ToString('N')
)
$previousMarker = $env:NEURA_TEST_FLUTTER_PROBE_MARKER
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
try {
  $staged = Join-Path $fixtureRoot 'stage-cold'
  $destination = Join-Path $fixtureRoot 'cold/3.47.5/x64'
  New-TestFlutterSdk -Root $staged
  Install-NeuraFlutterStagedSdk -StagedRoot $staged -Destination $destination -ExpectedVersion '3.47.5'
  if (-not (Test-Path (Join-Path $destination 'bin/flutter.bat')) -or (Test-Path $staged)) {
    throw 'Cold-cache promotion did not create the version directory and move the SDK.'
  }
  Write-Host 'PASS: cold cache creates the missing version parent.'

  Set-Content -LiteralPath (Join-Path $destination 'old-sdk.txt') -Value 'old'
  $staged = Join-Path $fixtureRoot 'stage-replacement'
  New-TestFlutterSdk -Root $staged
  Install-NeuraFlutterStagedSdk -StagedRoot $staged -Destination $destination -ExpectedVersion '3.47.5'
  if ((Test-Path "$destination.previous") -or (Test-Path (Join-Path $destination 'old-sdk.txt'))) {
    throw 'Successful replacement retained the old cache.'
  }
  Write-Host 'PASS: healthy replacement commits and removes its backup.'

  $sentinel = Join-Path $destination 'old-sdk.txt'
  Set-Content -LiteralPath $sentinel -Value 'keep'
  $staged = Join-Path $fixtureRoot 'stage-unhealthy'
  New-TestFlutterSdk -Root $staged -Unhealthy
  Assert-TestThrows -Action {
    Install-NeuraFlutterStagedSdk -StagedRoot $staged -Destination $destination -ExpectedVersion '3.47.5'
  } -MessagePattern 'staged.*failed its health probe'
  if (-not (Test-Path $sentinel)) { throw 'A bad staged SDK replaced the retained cache.' }
  Write-Host 'PASS: unhealthy staging leaves the retained cache intact.'

  $staged = Join-Path $fixtureRoot 'stage-fails-after-move'
  $env:NEURA_TEST_FLUTTER_PROBE_MARKER = Join-Path $fixtureRoot 'probe-marker'
  New-TestFlutterSdk -Root $staged -FailAfterMove
  Assert-TestThrows -Action {
    Install-NeuraFlutterStagedSdk -StagedRoot $staged -Destination $destination -ExpectedVersion '3.47.5'
  } -MessagePattern 'installed.*failed its health probe'
  if (-not (Test-Path $sentinel) -or (Test-Path "$destination.previous")) {
    throw 'The previous cache was not restored after the installed probe failed.'
  }
  Write-Host 'PASS: failed installed health probe rolls back.'

  $archiveSource = Join-Path $fixtureRoot 'archive-source'
  New-Item -ItemType Directory -Path $archiveSource | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $archiveSource 'one.bin'), [byte[]](1, 2, 3))
  [IO.File]::WriteAllBytes((Join-Path $archiveSource 'two.bin'), [byte[]](4, 5))
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archivePath = Join-Path $fixtureRoot 'fixture.zip'
  [IO.Compression.ZipFile]::CreateFromDirectory($archiveSource, $archivePath)
  if ((Get-NeuraFlutterExpandedBytes -ArchivePath $archivePath) -ne 5) {
    throw 'Expansion budget did not sum uncompressed archive sizes.'
  }
  Remove-Item -LiteralPath $archivePath
  Write-Host 'PASS: extraction budget uses uncompressed bytes and releases the ZIP handle.'

  Assert-NeuraFlutterInstallSpace -Path $fixtureRoot -MinimumBytes 1
  Assert-TestThrows -Action {
    Assert-NeuraFlutterInstallSpace -Path $fixtureRoot -MinimumBytes ([long]::MaxValue)
  } -MessagePattern 'needs.*free on cache volume'
  Write-Host 'PASS: the space guard accepts available capacity and rejects insufficient capacity.'

  # Fake only native curl's exit status and output; retain the real retry and
  # partial-file cleanup logic. Do not make network calls or sleep in tests.
  function Get-Command {
    param([string]$Name, $ErrorAction)
    if ($Name -ne 'curl.exe') { throw "Unexpected command lookup: $Name" }
    return [pscustomobject]@{ Source = 'Invoke-TestCurl' }
  }
  function Start-Sleep { param([int]$Seconds) }
  function Invoke-TestCurl {
    $outputIndex = [array]::IndexOf($args, '--output')
    Set-Content -LiteralPath $args[$outputIndex + 1] -Value 'partial download'
    $script:downloadAttempts++
    $global:LASTEXITCODE = $script:fakeCurlExitCode
  }
  $archivePath = Join-Path $fixtureRoot 'partial.zip'
  $script:downloadAttempts = 0
  $script:fakeCurlExitCode = 23
  Assert-TestThrows -Action {
    Get-NeuraFlutterArchive -Uri 'https://example.invalid/flutter.zip' -Destination $archivePath
  } -MessagePattern 'code 23'
  if ($script:downloadAttempts -ne 1 -or (Test-Path $archivePath)) {
    throw 'A local write failure was retried or left a partial download.'
  }
  Write-Host 'PASS: curl write failure is not retried and the partial archive is removed.'

  $script:downloadAttempts = 0
  $script:fakeCurlExitCode = 7
  Assert-TestThrows -Action {
    Get-NeuraFlutterArchive -Uri 'https://example.invalid/flutter.zip' -Destination $archivePath
  } -MessagePattern 'code 7'
  if ($script:downloadAttempts -ne 3 -or (Test-Path $archivePath)) {
    throw 'Network retry bounds or final partial cleanup changed.'
  }
  Write-Host 'PASS: network failures retain three attempts and remove the final partial archive.'
  $global:LASTEXITCODE = 0
} finally {
  $env:NEURA_TEST_FLUTTER_PROBE_MARKER = $previousMarker
  Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
