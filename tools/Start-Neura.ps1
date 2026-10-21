#Requires -Version 5.1
<#
.SYNOPSIS
Starts Neura on Windows in the right order: build the engine and app when
needed, then launch the app, which starts its own engine.

.DESCRIPTION
1. If Neura is already running, does nothing.
2. Builds when the app or engine is missing, when the source changed since the
   last launcher build (git HEAD), or when -Rebuild is passed. The release
   build (`flutter build windows --release`) compiles the Rust engine first
   (neura_swarm.dll and neura_api.exe) and places it next to the app.
3. Reports whether a local Ollama daemon is answering. Neura never starts or
   installs Ollama or a model; that stays the operator's choice.
4. Launches neuro_companion.exe. The app starts the engine itself, with a fresh
   session credential, when the Console asks for it. The engine must not be
   started on its own: without that credential it refuses to run.
#>
[CmdletBinding()]
param(
    [switch]$Rebuild,
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
$appExe = Join-Path $releaseDir 'neuro_companion.exe'
$required = @(
    $appExe,
    (Join-Path $releaseDir 'neura_api.exe'),
    (Join-Path $releaseDir 'neura_swarm.dll')
)
$stampFile = Join-Path $root 'build\neura_launcher.stamp'

function Write-Step([string]$Text) {
    Write-Host "[Neura] $Text" -ForegroundColor Magenta
}

function Get-SourceStamp {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $head = & git -C $root rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $head) { return $null }
    return ($head | Select-Object -First 1).Trim()
}

function Get-RunningNeura {
    Get-Process -Name 'neuro_companion' -ErrorAction SilentlyContinue |
        Where-Object {
            try { $_.Path -and ((Resolve-Path $_.Path).Path -eq $appExe) } catch { $false }
        }
}

function Test-OllamaListening {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1', 11434, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(500)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# 1. Already running?
$running = @(Get-RunningNeura)
if ($running.Count -gt 0) {
    Write-Step 'Neura is already running.'
    exit 0
}

# 2. Build the engine and app when needed.
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
$stamp = Get-SourceStamp
$lastStamp = if (Test-Path -LiteralPath $stampFile) {
    (Get-Content -LiteralPath $stampFile -Raw).Trim()
} else { '' }

$reason = $null
if ($Rebuild) { $reason = 'rebuild requested' }
elseif ($missing.Count -gt 0) { $reason = 'first build (app or engine not built yet)' }
elseif ($stamp -and $stamp -ne $lastStamp) { $reason = 'source changed since the last build' }

if ($reason) {
    Write-Step "Building Neura: $reason. This can take several minutes."
    foreach ($tool in 'flutter', 'cargo') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "$tool is required to build Neura. Install it, then run the launcher again."
        }
    }

    Push-Location $root
    try {
        Write-Step 'Step 1/2: fetching app packages'
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

        Write-Step 'Step 2/2: building the Rust engine, then the app'
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
    } finally {
        Pop-Location
    }

    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        throw "The build finished but these files are missing: $($missing -join ', ')"
    }
    if ($stamp) {
        Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ASCII
    }
    Write-Step 'Engine and app built.'
} else {
    Write-Step 'Engine and app are up to date.'
}

# 3. Local model daemon (informational only).
if (Test-OllamaListening) {
    Write-Step 'Local Ollama daemon is answering; the Console local model check can use it.'
} else {
    Write-Step 'Ollama is not running. Neura works without it; start Ollama yourself before a local model check.'
}

# 4. Launch the app; it starts its own engine.
if ($NoLaunch) {
    Write-Step "Ready: $appExe"
    exit 0
}
Write-Step 'Starting Neura...'
Start-Process -FilePath $appExe -WorkingDirectory $releaseDir | Out-Null
