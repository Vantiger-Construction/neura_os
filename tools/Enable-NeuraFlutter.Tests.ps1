#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
  throw 'Run these native batch-file regressions on Windows PowerShell.'
}

# Load only the health probe: tests must not install an SDK or touch its cache.
$scriptPath = Join-Path $PSScriptRoot 'Enable-NeuraFlutter.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  $scriptPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
  throw "Flutter provisioning script has syntax errors: $parseErrors"
}
$probe = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Test-NeuraFlutterSdk'
}, $true)
if ($null -eq $probe) { throw 'Flutter health probe is missing.' }
. ([scriptblock]::Create($probe.Extent.Text))

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) (
  'neura flutter probe ' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
  if (Test-NeuraFlutterSdk -Executable (Join-Path $fixtureRoot 'missing.bat') `
      -ExpectedVersion '3.47.5') {
    throw 'A missing SDK passed its health probe.'
  }

  $cases = @(
    @{ Name = 'bootstrap-stderr'; Banner = 'Flutter 3.47.5 - stable'; Code = 0; Healthy = $true },
    @{ Name = 'wrong-version'; Banner = 'Flutter 3.44.7 - stable'; Code = 0; Healthy = $false },
    @{ Name = 'version-prefix'; Banner = 'Flutter 3.47.50 - stable'; Code = 0; Healthy = $false },
    @{ Name = 'failed-command'; Banner = 'Flutter 3.47.5 - stable'; Code = 1; Healthy = $false },
    @{ Name = 'missing-banner'; Banner = 'Building flutter tool'; Code = 0; Healthy = $false },
    @{ Name = 'healthy-after-failure'; Banner = 'Flutter 3.47.5 - stable'; Code = 0; Healthy = $true }
  )
  foreach ($case in $cases) {
    $executable = Join-Path $fixtureRoot ($case.Name + '.bat')
    @(
      '@echo off',
      'echo Building flutter tool... 1>&2',
      ('echo ' + $case.Banner),
      ('exit /b ' + $case.Code)
    ) | Set-Content -LiteralPath $executable -Encoding Ascii
    $actual = Test-NeuraFlutterSdk -Executable $executable -ExpectedVersion '3.47.5'
    if ($actual -ne $case.Healthy) {
      throw "Incorrect SDK health result for $($case.Name): $actual"
    }
    if ($ErrorActionPreference -ne 'Stop') {
      throw "The probe changed the caller's error policy for $($case.Name)."
    }
  }
  Write-Host 'All 7 Flutter health-probe regressions passed.'
} finally {
  Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
