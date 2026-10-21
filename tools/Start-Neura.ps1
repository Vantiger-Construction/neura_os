#Requires -Version 5.1
<#
.SYNOPSIS
Starts Neura on Windows in the right order: validate or build the engine and
app, then launch the app, which starts its own engine.

.DESCRIPTION
1. Serializes launcher work and exits when this Neura build is already running.
2. Rebuilds when the complete runtime payload is invalid, source inputs changed,
   or -Rebuild is passed. Git worktree content is fingerprinted when available;
   source exports use a deterministic file-content fallback.
3. Verifies Ollama with a bounded, proxy-disabled loopback version request.
4. Launches neuro_companion.exe. The app owns the fresh engine credential and
   the engine is never started directly.
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
$stampFile = Join-Path $root 'build\neura_launcher.stamp'

function Write-Step([string]$Text) {
    Write-Host "[Neura] $Text" -ForegroundColor Magenta
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return (-join ($algorithm.ComputeHash($bytes) |
            ForEach-Object { $_.ToString('x2') }))
    } finally {
        $algorithm.Dispose()
    }
}

function Get-FilesystemSourceStamp {
    $sourcePaths = @(
        'pubspec.yaml',
        'pubspec.lock',
        'lib',
        'assets',
        'rust\Cargo.toml',
        'rust\Cargo.lock',
        'rust\build.rs',
        'rust\src',
        'rust\tests',
        'windows\CMakeLists.txt',
        'windows\runner',
        'windows\flutter\CMakeLists.txt',
        'windows\flutter\generated_plugin_registrant.cc',
        'windows\flutter\generated_plugin_registrant.h',
        'windows\flutter\generated_plugins.cmake'
    )

    $candidates = @(
        foreach ($relativePath in $sourcePaths) {
            $path = Join-Path $root $relativePath
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Get-Item -LiteralPath $path -Force
            } elseif (Test-Path -LiteralPath $path -PathType Container) {
                Get-ChildItem -LiteralPath $path -File -Recurse -Force
            }
        }
    )
    $files = @($candidates | Sort-Object -Property FullName -Unique)
    if ($files.Count -eq 0) {
        throw 'No Neura source inputs were found for build freshness validation.'
    }

    $lines = @(
        foreach ($file in $files) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing linked source input during build validation: $($file.FullName)"
            }
            $relative = $file.FullName.Substring($root.Length) -replace '^[\\/]+', ''
            $relative = $relative.Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            '{0}|{1}|{2}' -f $relative, $file.Length, $hash
        }
    )
    return ('files:{0}' -f (Get-TextSha256 -Text ($lines -join [Environment]::NewLine)))
}

function Get-SourceStamp {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $headOutput = @(& git -C $root rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $headOutput.Count -gt 0) {
            $head = ([string]$headOutput[0]).Trim()
            $diff = @(& git -C $root diff --no-ext-diff --binary HEAD -- 2>$null)
            if ($LASTEXITCODE -ne 0) {
                return (Get-FilesystemSourceStamp)
            }
            $untracked = @(
                & git -C $root -c core.quotepath=false ls-files --others --exclude-standard 2>$null
            )
            if ($LASTEXITCODE -ne 0) {
                return (Get-FilesystemSourceStamp)
            }
            $submodules = @(& git -C $root submodule status --recursive 2>$null)
            if ($LASTEXITCODE -ne 0) {
                return (Get-FilesystemSourceStamp)
            }

            $parts = New-Object 'System.Collections.Generic.List[string]'
            [void]$parts.Add("head:$head")
            foreach ($line in $diff) {
                [void]$parts.Add("diff:$line")
            }
            foreach ($line in $submodules) {
                [void]$parts.Add("submodule:$line")
            }
            foreach ($relativePath in ($untracked | Sort-Object)) {
                $path = Join-Path $root $relativePath
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                    throw "Untracked source input changed during fingerprinting: $relativePath"
                }
                $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                [void]$parts.Add(('untracked:{0}:{1}' -f $relativePath, $hash))
            }
            return ('git:{0}' -f (Get-TextSha256 -Text (
                $parts -join [Environment]::NewLine
            )))
        }
    }
    return (Get-FilesystemSourceStamp)
}

function Test-NeuraPayloadFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    return (
        $item.Length -gt 0 -and
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
    )
}

function Test-NeuraPayloadDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $false
    }
    return ($null -ne (Get-ChildItem -LiteralPath $Path -File -Recurse -Force |
        Where-Object {
            $_.Length -gt 0 -and
            ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
        } |
        Select-Object -First 1))
}

function Get-IncompleteNeuraPayload {
    $missing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in @(
        'neuro_companion.exe',
        'neura_api.exe',
        'neura_swarm.dll',
        'flutter_windows.dll',
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'data\icudtl.dat',
        'data\app.so'
    )) {
        $path = Join-Path $releaseDir $relativePath
        if (-not (Test-NeuraPayloadFile -Path $path)) {
            [void]$missing.Add($path)
        }
    }

    $assets = Join-Path $releaseDir 'data\flutter_assets'
    if (-not (Test-NeuraPayloadDirectory -Path $assets)) {
        [void]$missing.Add($assets)
    }
    return $missing
}

function Get-RunningNeura {
    Get-Process -Name 'neuro_companion' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -and
                    ((Resolve-Path -LiteralPath $_.Path).Path -eq
                        (Resolve-Path -LiteralPath $appExe -ErrorAction Stop).Path)
            } catch {
                $false
            }
        }
}

function Test-OllamaListening {
    $handler = $null
    $client = $null
    $response = $null
    try {
        Add-Type -AssemblyName System.Net.Http
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.UseProxy = $false
        $handler.AllowAutoRedirect = $false
        $client = [Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromMilliseconds(1200)
        $client.MaxResponseContentBufferSize = 4096
        $response = $client.GetAsync(
            'http://127.0.0.1:11434/api/version'
        ).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            return $false
        }
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($body) -or $body.Length -gt 4096) {
            return $false
        }
        $payload = $body | ConvertFrom-Json
        return (-not [string]::IsNullOrWhiteSpace([string]$payload.version))
    } catch {
        return $false
    } finally {
        if ($response) { $response.Dispose() }
        if ($client) {
            $client.Dispose()
        } elseif ($handler) {
            $handler.Dispose()
        }
    }
}

$mutexSuffix = (Get-TextSha256 -Text ($root.ToUpperInvariant())).Substring(0, 24)
$launcherMutex = [Threading.Mutex]::new(
    $false,
    "NeuraCompanionLauncher-$mutexSuffix"
)
$mutexHeld = $false
try {
    try {
        $mutexHeld = $launcherMutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $mutexHeld = $true
    }
    if (-not $mutexHeld) {
        Write-Step 'Another Neura launch or build is already in progress.'
        return
    }

    $running = @(Get-RunningNeura)
    if ($running.Count -gt 0) {
        if ($Rebuild) {
            throw 'Close Neura before requesting a rebuild.'
        }
        Write-Step 'Neura is already running.'
        return
    }

    $incomplete = @(Get-IncompleteNeuraPayload)
    $stamp = Get-SourceStamp
    $lastStamp = if (Test-Path -LiteralPath $stampFile -PathType Leaf) {
        $stampItem = Get-Item -LiteralPath $stampFile -Force
        if (($stampItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing linked build stamp: $stampFile"
        }
        (Get-Content -LiteralPath $stampFile -Raw).Trim()
    } else {
        ''
    }

    $reason = $null
    if ($Rebuild) {
        $reason = 'rebuild requested'
    } elseif ($incomplete.Count -gt 0) {
        $reason = 'runtime payload is missing or invalid'
    } elseif ($stamp -ne $lastStamp) {
        $reason = 'source changed since the last verified build'
    }

    if ($reason) {
        Write-Step "Building Neura: $reason. This can take several minutes."
        foreach ($tool in 'flutter', 'cargo') {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                throw "$tool is required to build Neura. Install it, then run the launcher again."
            }
        }

        Push-Location $root
        try {
            Write-Step 'Step 1/2: verifying locked app packages'
            & flutter pub get --enforce-lockfile
            if ($LASTEXITCODE -ne 0) {
                throw 'flutter pub get --enforce-lockfile failed.'
            }

            Write-Step 'Step 2/2: building the Rust engine, then the app'
            & flutter build windows --release
            if ($LASTEXITCODE -ne 0) {
                throw 'flutter build windows failed.'
            }
        } finally {
            Pop-Location
        }

        $incomplete = @(Get-IncompleteNeuraPayload)
        if ($incomplete.Count -gt 0) {
            throw "The build produced an incomplete runtime payload: $($incomplete -join ', ')"
        }
        $postBuildStamp = Get-SourceStamp
        if ($postBuildStamp -ne $stamp) {
            throw 'Source inputs changed during the build. Run the launcher again.'
        }
        Set-Content -LiteralPath $stampFile -Value $postBuildStamp -Encoding ASCII -NoNewline
        Write-Step 'Engine and app built and verified.'
    } else {
        Write-Step 'Engine and app are up to date and complete.'
    }

    if (Test-OllamaListening) {
        Write-Step 'Local Ollama API is answering; the Console local model check can use it.'
    } else {
        Write-Step 'Ollama is unavailable. Neura works without it; start Ollama yourself before a local model check.'
    }

    if ($NoLaunch) {
        Write-Step "Ready: $appExe"
        return
    }

    Write-Step 'Starting Neura...'
    $process = Start-Process -FilePath $appExe -WorkingDirectory $releaseDir -PassThru
    if (-not $process) {
        throw 'Windows did not create the Neura process.'
    }
    Start-Sleep -Milliseconds 250
    $process.Refresh()
    if ($process.HasExited -and $process.ExitCode -ne 0) {
        throw "Neura exited during startup with code $($process.ExitCode)."
    }
} finally {
    if ($mutexHeld) {
        try {
            $launcherMutex.ReleaseMutex()
        } catch {
            Write-Warning "Could not release the Neura launcher mutex: $($_.Exception.Message)"
        }
    }
    $launcherMutex.Dispose()
}
