param(
    [string]$WorkflowPath = (Join-Path $PSScriptRoot '..\.github\workflows\neura-fast-check.yml'),
    [switch]$ValidateInstalledToolchain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Exercise the actual inline CI step, including the runner's exit-code footer.
$workflow = Get-Content -LiteralPath $WorkflowPath -Raw
$match = [regex]::Match($workflow, '(?ms)^      - name: Ensure existing Visual C\+\+ build tools\r?\n.*?        run: \|\r?\n(?<body>.*?)(?=^      - name:)')
if (-not $match.Success) { throw 'Could not find the Visual C++ discovery step.' }
$body = [regex]::Replace($match.Groups['body'].Value, '(?m)^          ', '')
$footer = 'if (Test-Path -LiteralPath variable:\LASTEXITCODE) { exit $LASTEXITCODE }'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('neura-vswhere-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$stepPath = Join-Path $testRoot 'step.ps1'
Set-Content -LiteralPath $stepPath -Value ($body + "`r`n" + $footer) -Encoding UTF8
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Invoke-DiscoveryCase {
    param([string]$Name, [string]$ProgramFilesRoot, [string]$Installation,
        [int]$LocatorExit, [bool]$Success, [string]$ExpectedMessage)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $powershell
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $stepPath + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['ProgramFiles(x86)'] = $ProgramFilesRoot
    $start.EnvironmentVariables['NEURA_TEST_VS_PATH'] = $Installation
    $start.EnvironmentVariables['NEURA_TEST_VS_EXIT'] = [string]$LocatorExit
    $process = [Diagnostics.Process]::Start($start)
    $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $code = $process.ExitCode
    $process.Dispose()
    if (($Success -and $code -ne 0) -or (-not $Success -and $code -eq 0) -or
        -not $output.Contains($ExpectedMessage)) {
        throw "${Name}: unexpected exit ${code}: $output"
    }
    Write-Host "PASS ${Name}: exit $code"
}

try {
    $locatorDir = Join-Path $testRoot 'Microsoft Visual Studio\Installer'
    New-Item -ItemType Directory -Path $locatorDir -Force | Out-Null
    # A real native process exposes Select-Object's early pipeline termination.
    # Delaying after stdout makes the race deterministic without real VS changes.
    Add-Type -TypeDefinition @'
using System;
using System.Threading;
public static class LocatorFixture {
    public static int Main(string[] args) {
        string path = Environment.GetEnvironmentVariable("NEURA_TEST_VS_PATH");
        if (!String.IsNullOrEmpty(path)) {
            Console.WriteLine(path);
            Console.Out.Flush();
            Thread.Sleep(500);
            Console.WriteLine(path);
        }
        return Int32.Parse(Environment.GetEnvironmentVariable("NEURA_TEST_VS_EXIT"));
    }
}
'@ -OutputAssembly (Join-Path $locatorDir 'vswhere.exe') -OutputType ConsoleApplication
    $installation = Join-Path $testRoot 'synthetic-vs'
    $compilerDir = Join-Path $installation 'VC\Tools\MSVC\synthetic\bin'
    New-Item -ItemType Directory -Path $compilerDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $compilerDir 'cl.exe') -Value 'synthetic; never executed'
    Invoke-DiscoveryCase 'delayed native success' $testRoot $installation 0 $true 'Visual C++ compiler available'
    Invoke-DiscoveryCase 'native failure despite valid path' $testRoot $installation 7 $false 'Visual Studio locator failed with exit code 7'
    Invoke-DiscoveryCase 'no installation' $testRoot '' 0 $false 'A Visual Studio C++ toolchain installation is required'
    Invoke-DiscoveryCase 'missing compiler' $testRoot (Join-Path $testRoot 'no-compiler') 0 $false 'does not contain the MSVC compiler'
    Invoke-DiscoveryCase 'missing locator' (Join-Path $testRoot 'no-locator') '' 0 $false 'Visual Studio locator is missing'
    if ($ValidateInstalledToolchain) {
        Invoke-DiscoveryCase 'installed toolchain (read-only)' ${env:ProgramFiles(x86)} '' 0 $true 'Visual C++ compiler available'
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'neura-vswhere-test-*') {
        throw 'Refusing cleanup outside the disposable test root.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
