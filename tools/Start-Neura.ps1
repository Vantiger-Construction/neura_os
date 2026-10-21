#Requires -Version 5.1
<#
.SYNOPSIS
Starts Neura on Windows in the right order: validate or build the engine and
app, then launch the app, which starts its own engine.

.DESCRIPTION
1. Serializes launcher work and exits when this Neura build is already running.
2. Rebuilds when the complete runtime payload is invalid, source inputs changed,
   or -Rebuild is passed. Git worktrees and source exports use the same bounded
   build-input list so unrelated files cannot force or block a launch.
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
$buildDir = Join-Path $root 'build'
$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
$appExe = Join-Path $releaseDir 'neuro_companion.exe'
$stampFile = Join-Path $buildDir 'neura_launcher.stamp'
$payloadManifestFile = Join-Path $buildDir 'neura_launcher.payload.json'
$buildLockFile = Join-Path $buildDir 'neura_launcher.lock'
$sourcePaths = @(
    'pubspec.yaml',
    'pubspec.lock',
    'lib',
    'assets',
    'rust/Cargo.toml',
    'rust/Cargo.lock',
    'rust/build.rs',
    'rust/src',
    'rust/tests',
    'windows/CMakeLists.txt',
    'windows/cmake',
    'windows/runner',
    'windows/flutter/CMakeLists.txt',
    'tools/Start-NeuraLocalConversation.ps1',
    'tools/NeuraLocalConversationPolicy.ps1',
    'tools/NeuraLocalConversationProcess.cs'
)

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

function Invoke-QuietNative {
    param([Parameter(Mandatory)][scriptblock]$Command)

    # Windows PowerShell 5.1 turns redirected native stderr (git hints,
    # warnings, "fatal: not a git repository") into a terminating error under
    # ErrorActionPreference Stop. Callers check $LASTEXITCODE instead.
    $ErrorActionPreference = 'Continue'
    & $Command 2>$null
}

function Get-SourceStamp {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $headOutput = @(Invoke-QuietNative { & git -C $root rev-parse HEAD 2>$null })
        if ($LASTEXITCODE -eq 0 -and $headOutput.Count -gt 0) {
            $tree = @(Invoke-QuietNative {
                & git -C $root -c core.quotepath=false ls-tree -r `
                    --full-tree HEAD -- $sourcePaths 2>$null
            })
            if ($LASTEXITCODE -ne 0) {
                return (Get-FilesystemSourceStamp)
            }
            $changed = @(Invoke-QuietNative {
                & git -C $root -c core.quotepath=false diff --no-ext-diff `
                    --name-only HEAD -- $sourcePaths 2>$null
            })
            if ($LASTEXITCODE -ne 0) {
                return (Get-FilesystemSourceStamp)
            }
            $untracked = @(Invoke-QuietNative {
                & git -C $root -c core.quotepath=false ls-files --others `
                    -- $sourcePaths 2>$null
            })
            if ($LASTEXITCODE -ne 0) {
                return (Get-FilesystemSourceStamp)
            }

            $parts = New-Object 'System.Collections.Generic.List[string]'
            foreach ($line in $tree) {
                [void]$parts.Add("tree:$line")
            }
            foreach ($relativePath in ($changed | Sort-Object -Unique)) {
                $path = Join-Path $root $relativePath
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                    [void]$parts.Add(('changed:{0}:{1}' -f $relativePath, $hash))
                } else {
                    [void]$parts.Add("deleted:$relativePath")
                }
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

function Get-NeuraPayloadFiles {
    if (-not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
        return
    }
    $releaseItem = Get-Item -LiteralPath $releaseDir -Force
    if (($releaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing linked release directory: $releaseDir"
    }
    foreach ($directory in @(
        Get-ChildItem -LiteralPath $releaseDir -Directory -Recurse -Force
    )) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing linked runtime directory: $($directory.FullName)"
        }
    }
    $debugExtensions = @(
        '.exp', '.iobj', '.ilk', '.ipdb', '.lib', '.obj', '.pdb', '.tlog'
    )
    Get-ChildItem -LiteralPath $releaseDir -File -Recurse -Force |
        Where-Object { $_.Extension -notin $debugExtensions }
}

function Get-NeuraPayloadManifest {
    if (-not (Test-Path -LiteralPath $payloadManifestFile -PathType Leaf)) {
        return $null
    }
    $item = Get-Item -LiteralPath $payloadManifestFile -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing linked payload manifest: $payloadManifestFile"
    }
    if ($item.Length -gt 16MB) {
        return $null
    }
    try {
        $raw = [string](Get-Content -LiteralPath $payloadManifestFile -Raw)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        $manifest = $raw | ConvertFrom-Json
        $manifestFiles = @($manifest.files)
        if ([int]$manifest.schema -ne 1 -or
            $manifestFiles.Count -eq 0 -or
            $manifestFiles.Count -gt 100000) {
            return $null
        }

        $releasePrefix = $releaseDir.TrimEnd('\') + '\'
        $paths = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($entry in $manifestFiles) {
            $relativePath = [string]$entry.path
            $length = [long]0
            $hash = ([string]$entry.sha256).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($relativePath) -or
                $relativePath -ne $relativePath.Trim() -or
                [IO.Path]::IsPathRooted($relativePath) -or
                $relativePath.IndexOf(':') -ge 0 -or
                -not [long]::TryParse([string]$entry.length, [ref]$length) -or
                $length -lt 0 -or
                ($length -eq 0 -and
                    [IO.Path]::GetExtension($relativePath) -in @('.dll', '.exe')) -or
                $hash -notmatch '^[0-9a-f]{64}$') {
                return $null
            }
            $path = [IO.Path]::GetFullPath((Join-Path $releaseDir $relativePath))
            if (-not $path.StartsWith(
                $releasePrefix,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                return $null
            }
            $normalizedRelative = $path.Substring($releasePrefix.Length) `
                -replace '\\', '/'
            if (-not $paths.Add($normalizedRelative)) {
                return $null
            }
        }
        return $manifest
    } catch {
        return $null
    }
}

function Get-NeuraPayloadManifestProblems {
    param(
        [AllowNull()][object]$Manifest,
        [switch]$PresenceOnly
    )

    $problems = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Manifest) {
        [void]$problems.Add($payloadManifestFile)
        return $problems
    }

    try {
        $actualFiles = @(Get-NeuraPayloadFiles)
    } catch {
        [void]$problems.Add($payloadManifestFile)
        return $problems
    }

    $releasePrefix = $releaseDir.TrimEnd('\') + '\'
    $expectedPaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($entry in @($Manifest.files)) {
        try {
            $relativePath = [string]$entry.path
            $expectedLength = [long]$entry.length
            $expectedHash = ([string]$entry.sha256).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($relativePath) -or
                $expectedLength -lt 0 -or
                ($expectedLength -eq 0 -and
                    [IO.Path]::GetExtension($relativePath) -in @('.dll', '.exe')) -or
                $expectedHash -notmatch '^[0-9a-f]{64}$') {
                throw 'Invalid payload entry.'
            }
            $path = [IO.Path]::GetFullPath((Join-Path $releaseDir $relativePath))
            if (-not $path.StartsWith(
                $releasePrefix,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                throw 'Payload entry escapes the release directory.'
            }
            $normalizedRelative = $path.Substring($releasePrefix.Length) `
                -replace '\\', '/'
            if (-not $expectedPaths.Add($normalizedRelative)) {
                throw 'Duplicate payload entry.'
            }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                [void]$problems.Add($path)
                continue
            }
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($item.Length -eq 0 -and
                    [IO.Path]::GetExtension($path) -in @('.dll', '.exe'))) {
                [void]$problems.Add($path)
                continue
            }
            if ($PresenceOnly) {
                continue
            }
            if ($item.Length -ne $expectedLength) {
                [void]$problems.Add($path)
                continue
            }
            $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $expectedHash) {
                [void]$problems.Add($path)
            }
        } catch {
            [void]$problems.Add($payloadManifestFile)
        }
    }
    if (-not $PresenceOnly) {
        foreach ($file in $actualFiles) {
            $relativePath = $file.FullName.Substring($releasePrefix.Length) `
                -replace '\\', '/'
            if (-not $expectedPaths.Contains($relativePath)) {
                [void]$problems.Add($file.FullName)
            }
        }
    }
    return $problems
}

function Write-NeuraPayloadManifest {
    $files = @(Get-NeuraPayloadFiles |
        Sort-Object -Property FullName -Unique)
    if ($files.Count -eq 0) {
        throw 'No packaged runtime files were found for the payload manifest.'
    }

    $entries = @(
        foreach ($file in $files) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing linked runtime payload: $($file.FullName)"
            }
            if ($file.Length -eq 0 -and $file.Extension -in @('.dll', '.exe')) {
                throw "Refusing empty runtime binary: $($file.FullName)"
            }
            $relativePath = $file.FullName.Substring($releaseDir.Length) `
                -replace '^[\\/]+', ''
            [PSCustomObject]@{
                path = $relativePath.Replace('\', '/')
                length = [long]$file.Length
                sha256 = (Get-FileHash -LiteralPath $file.FullName `
                    -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    )
    $document = [PSCustomObject]@{
        schema = 1
        files = $entries
    }
    $json = ConvertTo-Json -InputObject $document -Depth 4
    Set-Content -LiteralPath $payloadManifestFile -Value $json -Encoding UTF8
}

function Get-IncompleteNeuraPayload {
    param(
        [AllowNull()][object]$Manifest,
        [switch]$SkipManifest
    )

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
        'data\app.so',
        'data\flutter_assets\AssetManifest.bin',
        'offline-text\Start-NeuraLocalConversation.ps1',
        'offline-text\NeuraLocalConversationPolicy.ps1',
        'offline-text\NeuraLocalConversationProcess.cs'
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
    foreach ($supportName in @(
        'Start-NeuraLocalConversation.ps1',
        'NeuraLocalConversationPolicy.ps1',
        'NeuraLocalConversationProcess.cs'
    )) {
        $source = Join-Path (Join-Path $root 'tools') $supportName
        $packaged = Join-Path (Join-Path $releaseDir 'offline-text') $supportName
        if (-not (Test-NeuraPayloadFile -Path $source) -or
            -not (Test-NeuraPayloadFile -Path $packaged) -or
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $packaged -Algorithm SHA256).Hash) {
            [void]$missing.Add($packaged)
        }
    }
    if (-not $SkipManifest) {
        foreach ($problem in @(Get-NeuraPayloadManifestProblems -Manifest $Manifest)) {
            [void]$missing.Add($problem)
        }
    }
    return $missing
}

function Sync-NeuraLocalSupportFiles {
    $destinationDirectory = Join-Path $releaseDir 'offline-text'
    if (Test-Path -LiteralPath $destinationDirectory) {
        $directoryItem = Get-Item -LiteralPath $destinationDirectory -Force
        if (-not $directoryItem.PSIsContainer -or
            ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing unsafe support directory: $destinationDirectory"
        }
    } else {
        New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
    }

    foreach ($supportName in @(
        'Start-NeuraLocalConversation.ps1',
        'NeuraLocalConversationPolicy.ps1',
        'NeuraLocalConversationProcess.cs'
    )) {
        $source = Join-Path (Join-Path $root 'tools') $supportName
        if (-not (Test-NeuraPayloadFile -Path $source)) {
            throw "Local conversation support input is missing: $source"
        }
        $destination = Join-Path $destinationDirectory $supportName
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing linked support destination: $destination"
            }
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
                Remove-Item -LiteralPath $destination -Recurse -Force
            }
        }
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

function Ensure-NeuraRuntimeLibraries {
    $runtimeNames = @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )
    $candidates = @(
        foreach ($programRoot in @(
            [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),
            $env:ProgramFiles
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
            Get-ChildItem -Path (
                Join-Path $programRoot (
                    "Microsoft Visual Studio\*\*\VC\Redist\MSVC\*" +
                    '\x64\Microsoft.VC*.CRT'
                )
            ) -Directory -ErrorAction SilentlyContinue
        }
    )
    $sets = @(
        foreach ($directory in $candidates) {
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            $complete = $true
            foreach ($runtimeName in $runtimeNames) {
                $source = Join-Path $directory.FullName $runtimeName
                if (-not (Test-NeuraPayloadFile -Path $source)) {
                    $complete = $false
                    break
                }
            }
            if ($complete) {
                $version = [version]'0.0'
                $parsedVersion = [version]'0.0'
                if ([version]::TryParse(
                    $directory.Parent.Parent.Name,
                    [ref]$parsedVersion
                )) {
                    $version = $parsedVersion
                }
                [PSCustomObject]@{
                    Directory = $directory
                    Version = $version
                }
            }
        }
    )
    $selected = $sets | Sort-Object -Property `
        @{ Expression = { $_.Version }; Descending = $true }, `
        @{ Expression = { $_.Directory.FullName }; Descending = $true } |
        Select-Object -First 1
    if (-not $selected) {
        throw 'A complete Visual C++ x64 runtime set was not found.'
    }

    foreach ($runtimeName in $runtimeNames) {
        $source = Join-Path $selected.Directory.FullName $runtimeName
        $destination = Join-Path $releaseDir $runtimeName
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing linked runtime destination: $destination"
            }
            if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
                Remove-Item -LiteralPath $destination -Recurse -Force
            }
        }
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
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
$buildLock = $null
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

    if (Test-Path -LiteralPath $buildDir) {
        $buildItem = Get-Item -LiteralPath $buildDir -Force
        if (-not $buildItem.PSIsContainer -or
            ($buildItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing unsafe build directory: $buildDir"
        }
    } else {
        New-Item -ItemType Directory -Path $buildDir | Out-Null
    }
    if (Test-Path -LiteralPath $buildLockFile) {
        $lockItem = Get-Item -LiteralPath $buildLockFile -Force
        if ($lockItem.PSIsContainer -or
            ($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing unsafe launcher lock: $buildLockFile"
        }
    }
    try {
        $buildLock = [IO.File]::Open(
            $buildLockFile,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    } catch [IO.IOException] {
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

    $payloadManifest = Get-NeuraPayloadManifest
    $incomplete = @(
        Get-IncompleteNeuraPayload -Manifest $payloadManifest
    )
    $stamp = Get-SourceStamp
    $lastStamp = if (Test-Path -LiteralPath $stampFile -PathType Leaf) {
        $stampItem = Get-Item -LiteralPath $stampFile -Force
        if (($stampItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing linked build stamp: $stampFile"
        }
        ([string](Get-Content -LiteralPath $stampFile -Raw)).Trim()
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
        } finally {
            Pop-Location
        }

        if ((Get-SourceStamp) -ne $stamp) {
            throw (
                'Source inputs changed while verifying app packages. ' +
                'Run the launcher again.'
            )
        }

        $transactionId = [Guid]::NewGuid().ToString('N')
        $releaseBackupDir = Join-Path (Split-Path $releaseDir -Parent) `
            ("Release.neura-backup-$transactionId")
        $releaseFailedDir = Join-Path (Split-Path $releaseDir -Parent) `
            ("Release.neura-failed-$transactionId")
        $manifestBackupFile = "$payloadManifestFile.neura-backup-$transactionId"
        $manifestFailedFile = "$payloadManifestFile.neura-failed-$transactionId"
        $stampBackupFile = "$stampFile.neura-backup-$transactionId"
        $stampCandidateFile = "$stampFile.neura-candidate-$transactionId"
        $stampFailedFile = "$stampFile.neura-failed-$transactionId"
        $hadRelease = $false
        $hadManifest = $false
        $buildStarted = $false
        $buildCommitted = $false
        try {
            if (Test-Path -LiteralPath $releaseDir) {
                $releaseItem = Get-Item -LiteralPath $releaseDir -Force
                if (-not $releaseItem.PSIsContainer -or
                    ($releaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Refusing unsafe release directory: $releaseDir"
                }
                [void]@(Get-NeuraPayloadFiles)
                [IO.Directory]::Move($releaseDir, $releaseBackupDir)
                $hadRelease = $true
            }
            if (Test-Path -LiteralPath $payloadManifestFile) {
                $manifestItem = Get-Item -LiteralPath $payloadManifestFile -Force
                if ($manifestItem.PSIsContainer -or
                    ($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Refusing unsafe payload manifest: $payloadManifestFile"
                }
                [IO.File]::Move($payloadManifestFile, $manifestBackupFile)
                $hadManifest = $true
            }

            $buildStarted = $true
            Push-Location $root
            try {
                Write-Step 'Step 2/2: building the Rust engine, then the app'
                & flutter build windows --release
                if ($LASTEXITCODE -ne 0) {
                    throw 'flutter build windows failed.'
                }
            } finally {
                Pop-Location
            }

            Sync-NeuraLocalSupportFiles
            Ensure-NeuraRuntimeLibraries
            $incomplete = @(Get-IncompleteNeuraPayload -SkipManifest)
            if ($incomplete.Count -gt 0) {
                throw "The build produced an incomplete runtime payload: $($incomplete -join ', ')"
            }
            if ($payloadManifest -and $stamp -eq $lastStamp -and -not $Rebuild) {
                $unrepaired = @(
                    Get-NeuraPayloadManifestProblems -Manifest $payloadManifest `
                        -PresenceOnly
                )
                if ($unrepaired.Count -gt 0) {
                    throw (
                        'The build did not restore the previously verified payload: ' +
                        ($unrepaired -join ', ')
                    )
                }
            }
            Write-NeuraPayloadManifest
            $verifiedManifest = Get-NeuraPayloadManifest
            $incomplete = @(
                Get-IncompleteNeuraPayload -Manifest $verifiedManifest
            )
            if ($incomplete.Count -gt 0) {
                throw "The packaged runtime manifest is incomplete: $($incomplete -join ', ')"
            }

            $postBuildStamp = Get-SourceStamp
            if ($postBuildStamp -ne $stamp) {
                throw 'Source inputs changed during the build. Run the launcher again.'
            }

            $stampBytes = [Text.Encoding]::ASCII.GetBytes($postBuildStamp)
            $stampStream = [IO.File]::Open(
                $stampCandidateFile,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            try {
                $stampStream.Write($stampBytes, 0, $stampBytes.Length)
                $stampStream.Flush($true)
            } finally {
                $stampStream.Dispose()
            }
            if ((Get-SourceStamp) -ne $postBuildStamp) {
                throw 'Source inputs changed while committing the build. Run the launcher again.'
            }
            if (Test-Path -LiteralPath $stampFile) {
                $currentStampItem = Get-Item -LiteralPath $stampFile -Force
                if ($currentStampItem.PSIsContainer -or
                    ($currentStampItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Refusing unsafe build stamp: $stampFile"
                }
                [IO.File]::Replace(
                    $stampCandidateFile,
                    $stampFile,
                    $stampBackupFile
                )
            } else {
                [IO.File]::Move($stampCandidateFile, $stampFile)
            }
            $buildCommitted = $true
        } catch {
            $buildError = $_
            $recoveryProblems = New-Object 'System.Collections.Generic.List[string]'
            $failedArtifacts = New-Object 'System.Collections.Generic.List[string]'

            try {
                if (Test-Path -LiteralPath $stampCandidateFile) {
                    $candidateItem = Get-Item -LiteralPath $stampCandidateFile -Force
                    if ($candidateItem.PSIsContainer -or
                        ($candidateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "unsafe stamp candidate $stampCandidateFile"
                    }
                    Remove-Item -LiteralPath $stampCandidateFile -Force
                }
            } catch {
                [void]$recoveryProblems.Add(
                    "stamp candidate: $($_.Exception.Message)"
                )
            }
            try {
                if (Test-Path -LiteralPath $stampBackupFile) {
                    if (Test-Path -LiteralPath $stampFile) {
                        $currentStampItem = Get-Item -LiteralPath $stampFile -Force
                        if ($currentStampItem.PSIsContainer -or
                            ($currentStampItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                            throw "unsafe replacement stamp $stampFile"
                        }
                        [IO.File]::Move($stampFile, $stampFailedFile)
                        [void]$failedArtifacts.Add($stampFailedFile)
                    }
                    [IO.File]::Move($stampBackupFile, $stampFile)
                }
            } catch {
                [void]$recoveryProblems.Add(
                    "build stamp: $($_.Exception.Message)"
                )
            }

            try {
                if (($hadManifest -or $buildStarted) -and
                    (Test-Path -LiteralPath $payloadManifestFile)) {
                    $newManifestItem = Get-Item -LiteralPath $payloadManifestFile -Force
                    if ($newManifestItem.PSIsContainer -or
                        ($newManifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "unsafe replacement manifest $payloadManifestFile"
                    }
                    [IO.File]::Move($payloadManifestFile, $manifestFailedFile)
                    [void]$failedArtifacts.Add($manifestFailedFile)
                }
                if ($hadManifest) {
                    if (-not (Test-Path -LiteralPath $manifestBackupFile -PathType Leaf)) {
                        throw "missing manifest backup $manifestBackupFile"
                    }
                    [IO.File]::Move($manifestBackupFile, $payloadManifestFile)
                }
            } catch {
                [void]$recoveryProblems.Add(
                    "payload manifest: $($_.Exception.Message)"
                )
            }

            try {
                if (($hadRelease -or $buildStarted) -and
                    (Test-Path -LiteralPath $releaseDir)) {
                    [void]@(Get-NeuraPayloadFiles)
                    [IO.Directory]::Move($releaseDir, $releaseFailedDir)
                    [void]$failedArtifacts.Add($releaseFailedDir)
                }
                if ($hadRelease) {
                    if (-not (Test-Path -LiteralPath $releaseBackupDir -PathType Container)) {
                        throw "missing release backup $releaseBackupDir"
                    }
                    [IO.Directory]::Move($releaseBackupDir, $releaseDir)
                }
            } catch {
                [void]$recoveryProblems.Add(
                    "release bundle: $($_.Exception.Message)"
                )
            }

            if ($recoveryProblems.Count -eq 0) {
                foreach ($failedArtifact in $failedArtifacts) {
                    try {
                        if (Test-Path -LiteralPath $failedArtifact) {
                            $failedItem = Get-Item -LiteralPath $failedArtifact -Force
                            if (($failedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                                throw "Refusing linked failed artifact: $failedArtifact"
                            }
                            Remove-Item -LiteralPath $failedArtifact -Recurse -Force
                        }
                    } catch {
                        Write-Warning (
                            'Rollback succeeded, but a failed build artifact could not be ' +
                            "removed: $failedArtifact ($($_.Exception.Message))"
                        )
                    }
                }
            }
            if ($recoveryProblems.Count -gt 0) {
                $recoveryPaths = @(
                    $releaseBackupDir,
                    $releaseFailedDir,
                    $manifestBackupFile,
                    $manifestFailedFile,
                    $stampBackupFile,
                    $stampCandidateFile,
                    $stampFailedFile
                ) -join ', '
                Write-Warning (
                    "Neura build failed: $($buildError.Exception.Message) " +
                    'Automatic rollback was incomplete. Inspect any existing recovery ' +
                    "paths before retrying: $recoveryPaths. Problems: " +
                    ($recoveryProblems -join '; ')
                )
            }
            throw $buildError
        }

        if ($buildCommitted) {
            foreach ($backup in @(
                $releaseBackupDir,
                $manifestBackupFile,
                $stampBackupFile
            )) {
                try {
                    if (-not (Test-Path -LiteralPath $backup)) {
                        continue
                    }
                    $backupItem = Get-Item -LiteralPath $backup -Force
                    if (($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "Refusing linked transaction backup: $backup"
                    }
                    Remove-Item -LiteralPath $backup -Recurse -Force
                } catch {
                    Write-Warning (
                        "The verified build is ready, but an old backup could not be removed: " +
                        "$backup ($($_.Exception.Message))"
                    )
                }
            }
        }
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
    if ($process.HasExited) {
        if ($process.ExitCode -eq 0) {
            throw (
                'Neura exited immediately without opening. Another Neura ' +
                'instance may already be running.'
            )
        }
        throw "Neura exited during startup with code $($process.ExitCode)."
    }
} finally {
    if ($buildLock) {
        $buildLock.Dispose()
    }
    if ($mutexHeld) {
        try {
            $launcherMutex.ReleaseMutex()
        } catch {
            Write-Warning "Could not release the Neura launcher mutex: $($_.Exception.Message)"
        }
    }
    $launcherMutex.Dispose()
}
