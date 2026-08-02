[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DiagnosticsOnly,
    [switch]$SkipBuild,
    [switch]$SkipApiCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $PackageRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogDir "neura_improvement_$Stamp.log"
$ReportFile = Join-Path $LogDir "neura_report_$Stamp.json"

function Write-Step([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor Cyan
    Add-Content -LiteralPath $LogFile -Value $line
}

function Test-NeuraRoot([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $signals = @(
        'Assets', 'ProjectSettings', 'pubspec.yaml', 'Cargo.toml',
        'package.json', 'requirements.txt', 'pyproject.toml',
        'BUILD_ALL_NEURA_FULL.bat', 'neura_brain'
    )
    foreach ($signal in $signals) {
        if (Test-Path -LiteralPath (Join-Path $Path $signal)) { return $true }
    }
    return $false
}

function Find-NeuraRoot {
    param([string]$Requested)
    if ($Requested) {
        $resolved = (Resolve-Path -LiteralPath $Requested -ErrorAction Stop).Path
        if (-not (Test-NeuraRoot $resolved)) { throw "The supplied root does not look like a Neura project: $resolved" }
        return $resolved
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add((Split-Path -Parent $PackageRoot))
    $candidates.Add($PackageRoot)
    foreach ($p in @(
        'C:\Neura', 'C:\NEURA_v2.0\Neura_Complete_v2',
        'D:\Neura', 'D:\Vantiger1\neura_os',
        "$env:USERPROFILE\Vantiger Construction\Neura Companion",
        "$env:USERPROFILE\Vantiger Construction\Neura Companion OS",
        "$env:USERPROFILE\Documents\Neura",
        "$env:USERPROFILE\Desktop\Neura"
    )) { if ($p) { $candidates.Add($p) } }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-NeuraRoot $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($name in @('Neura','Neura Companion','Neura Companion OS','neura_os')) {
            $candidate = Join-Path $drive.Root $name
            if (Test-NeuraRoot $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
    }
    throw 'No validated Neura project root was found. Re-run with -Root "C:\path\to\Neura".'
}

function Get-CommandVersion([string]$Name, [string[]]$Args) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    try { return (& $Name @Args 2>&1 | Select-Object -First 1 | Out-String).Trim() } catch { return 'installed (version unavailable)' }
}

$ProjectRoot = Find-NeuraRoot -Requested $Root
Write-Step "Validated Neura root: $ProjectRoot"

$report = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    projectRoot = $ProjectRoot
    components = [ordered]@{}
    tools = [ordered]@{}
    api = [ordered]@{}
    build = [ordered]@{ attempted = $false; result = 'not-run' }
}

$report.components.unity = (Test-Path (Join-Path $ProjectRoot 'Assets')) -and (Test-Path (Join-Path $ProjectRoot 'ProjectSettings'))
$report.components.flutter = Test-Path (Join-Path $ProjectRoot 'pubspec.yaml')
$report.components.rust = Test-Path (Join-Path $ProjectRoot 'Cargo.toml')
$report.components.node = Test-Path (Join-Path $ProjectRoot 'package.json')
$report.components.python = (Test-Path (Join-Path $ProjectRoot 'requirements.txt')) -or (Test-Path (Join-Path $ProjectRoot 'pyproject.toml'))
$report.components.fullBuildScript = Test-Path (Join-Path $ProjectRoot 'BUILD_ALL_NEURA_FULL.bat')

$report.tools.git = Get-CommandVersion 'git' @('--version')
$report.tools.dotnet = Get-CommandVersion 'dotnet' @('--version')
$report.tools.node = Get-CommandVersion 'node' @('--version')
$report.tools.python = Get-CommandVersion 'python' @('--version')
$report.tools.flutter = Get-CommandVersion 'flutter' @('--version')
$report.tools.cargo = Get-CommandVersion 'cargo' @('--version')

if (-not $SkipApiCheck) {
    foreach ($entry in @(
        @{ Name='core'; Url='http://127.0.0.1:8000/health' },
        @{ Name='advanced'; Url='http://127.0.0.1:8799/health' }
    )) {
        try {
            $r = Invoke-WebRequest -Uri $entry.Url -UseBasicParsing -TimeoutSec 3
            $report.api[$entry.Name] = "HTTP $($r.StatusCode)"
        } catch {
            $report.api[$entry.Name] = 'offline-or-no-health-route'
        }
    }
}

if (-not $DiagnosticsOnly -and -not $SkipBuild) {
    $report.build.attempted = $true
    Push-Location $ProjectRoot
    try {
        if (Test-Path '.\BUILD_ALL_NEURA_FULL.bat') {
            Write-Step 'Running existing BUILD_ALL_NEURA_FULL.bat'
            & cmd.exe /d /c '.\BUILD_ALL_NEURA_FULL.bat' 2>&1 | Tee-Object -FilePath $LogFile -Append
            if ($LASTEXITCODE -ne 0) { throw "Full build script failed with exit code $LASTEXITCODE" }
            $report.build.result = 'success'
        } elseif ($report.components.flutter -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
            Write-Step 'No master build script found; running guarded Flutter validation.'
            & flutter pub get 2>&1 | Tee-Object -FilePath $LogFile -Append
            if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
            & flutter analyze 2>&1 | Tee-Object -FilePath $LogFile -Append
            if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
            $report.build.result = 'validation-success'
        } else {
            $report.build.result = 'no-supported-build-entrypoint-found'
            Write-Step 'No safe automated build entry point was found; diagnostics completed.'
        }
    } catch {
        $report.build.result = 'failed'
        $report.build.error = $_.Exception.Message
        Write-Step "Build failed: $($_.Exception.Message)"
    } finally {
        Pop-Location
    }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportFile -Encoding UTF8
Write-Step "Report written: $ReportFile"
Write-Host "`nComponent summary:" -ForegroundColor Green
$report.components.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-18} {1}" -f $_.Key, $_.Value) }
Write-Host "`nBuild result: $($report.build.result)" -ForegroundColor Yellow

if ($report.build.result -eq 'failed') { exit 1 }
exit 0
