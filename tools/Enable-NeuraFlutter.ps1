[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version,

  [Parameter(Mandatory)]
  [ValidatePattern('^[A-Fa-f0-9]{64}$')]
  [string]$ExpectedSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:RUNNER_TOOL_CACHE)) {
  throw 'RUNNER_TOOL_CACHE is unavailable; the pinned Flutter SDK cannot be installed safely.'
}

$cacheParent = Join-Path $env:RUNNER_TOOL_CACHE 'flutter'
$flutterRoot = Join-Path $cacheParent "$Version\x64"
$flutterExe = Join-Path $flutterRoot 'bin\flutter.bat'
$backupRoot = "$flutterRoot.previous"
$backupExe = Join-Path $backupRoot 'bin\flutter.bat'
$lockPath = Join-Path $cacheParent ".$Version.install.lock"
$expectedHash = $ExpectedSha256.ToLowerInvariant()

function Test-NeuraFlutterSdk {
  param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$ExpectedVersion
  )

  if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    return $false
  }

  $output = @(& $Executable --version 2>&1)
  return $LASTEXITCODE -eq 0 -and
    ($output -join [Environment]::NewLine) -match
      "Flutter $([regex]::Escape($ExpectedVersion))"
}

function Get-NeuraFlutterArchive {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$Destination
  )

  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
      if ($curl) {
        & $curl.Source `
          --fail `
          --location `
          --retry 2 `
          --retry-delay 5 `
          --connect-timeout 30 `
          --max-time 1800 `
          --output $Destination `
          $Uri
        if ($LASTEXITCODE -ne 0) {
          throw "curl.exe exited with code $LASTEXITCODE."
        }
      } else {
        Invoke-WebRequest `
          -UseBasicParsing `
          -Uri $Uri `
          -OutFile $Destination `
          -TimeoutSec 1800
      }
      return
    } catch {
      Write-Warning (
        "Flutter download {0}/3 failed: {1}" -f
        $attempt,
        $_.Exception.Message
      )
      if ($attempt -eq 3) {
        throw
      }
      Start-Sleep -Seconds (10 * $attempt)
    }
  }
}

New-Item -ItemType Directory -Path $cacheParent -Force | Out-Null
$lock = $null
$lockDeadline = [DateTime]::UtcNow.AddMinutes(30)
while (-not $lock) {
  try {
    $lock = [System.IO.File]::Open(
      $lockPath,
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
  } catch [System.IO.IOException] {
    if ([DateTime]::UtcNow -ge $lockDeadline) {
      throw "Timed out waiting for another Flutter $Version cache install to finish."
    }
    Start-Sleep -Seconds 5
  }
}

try {
  if (-not (Test-NeuraFlutterSdk -Executable $flutterExe -ExpectedVersion $Version) -and
      (Test-NeuraFlutterSdk -Executable $backupExe -ExpectedVersion $Version)) {
    Write-Warning "Recovering the previous healthy Flutter $Version cache."
    Remove-Item -LiteralPath $flutterRoot -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $backupRoot -Destination $flutterRoot
  }

  if (-not (Test-NeuraFlutterSdk -Executable $flutterExe -ExpectedVersion $Version)) {
    Write-Warning (
      "Retained Flutter $Version is missing or unhealthy; " +
      'installing a checksum-verified replacement.'
    )

    $releaseIndexUri =
      'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $releaseIndex = Invoke-RestMethod -UseBasicParsing -Uri $releaseIndexUri
    $release = $releaseIndex.releases |
      Where-Object {
        $_.version -eq $Version -and
        $_.channel -eq 'stable' -and
        $_.dart_sdk_arch -eq 'x64'
      } |
      Select-Object -First 1
    if (-not $release) {
      throw "Flutter $Version x64 is absent from the official stable release index."
    }

    $indexHash = ([string]$release.sha256).Trim().ToLowerInvariant()
    if ($indexHash -ne $expectedHash) {
      throw (
        "Flutter $Version release-index SHA-256 does not match the repository pin. " +
        "Expected $expectedHash; found $indexHash."
      )
    }

    $archiveUri =
      $releaseIndex.base_url.TrimEnd('/') + '/' + $release.archive
    $temporaryParent = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($temporaryParent) -or
        -not (Test-Path -LiteralPath $temporaryParent -PathType Container)) {
      $temporaryParent = $env:RUNNER_TEMP
    }
    $repairRoot = Join-Path $temporaryParent "neura-flutter-$Version-install"
    $archivePath = Join-Path $repairRoot 'flutter.zip'
    $extractRoot = Join-Path $repairRoot 'extract'
    $stagedFlutter = Join-Path $extractRoot 'flutter'

    Remove-Item -LiteralPath $repairRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    try {
      Get-NeuraFlutterArchive -Uri $archiveUri -Destination $archivePath

      $actualHash =
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($actualHash -ne $expectedHash) {
        throw (
          "Flutter $Version archive SHA-256 verification failed. " +
          "Expected $expectedHash; found $actualHash."
        )
      }

      $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
      if ($tar) {
        & $tar.Source -xf $archivePath -C $extractRoot
        if ($LASTEXITCODE -ne 0) {
          throw "tar.exe failed to extract Flutter with exit code $LASTEXITCODE."
        }
      } else {
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
      }

      $stagedExe = Join-Path $stagedFlutter 'bin\flutter.bat'
      if (-not (Test-NeuraFlutterSdk -Executable $stagedExe -ExpectedVersion $Version)) {
        throw "The staged Flutter $Version SDK failed its health probe."
      }

      Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
      if (Test-Path -LiteralPath $flutterRoot) {
        Move-Item -LiteralPath $flutterRoot -Destination $backupRoot
      }
      try {
        Move-Item -LiteralPath $stagedFlutter -Destination $flutterRoot
      } catch {
        if (Test-Path -LiteralPath $backupRoot) {
          Move-Item -LiteralPath $backupRoot -Destination $flutterRoot
        }
        throw
      }
      Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    } finally {
      Remove-Item -LiteralPath $repairRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  if (-not (Test-NeuraFlutterSdk -Executable $flutterExe -ExpectedVersion $Version)) {
    throw "Flutter $Version remains unavailable after cache provisioning."
  }
  Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue

  $flutterBin = Join-Path $flutterRoot 'bin'
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PATH)) {
    $flutterBin | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
  }
  & $flutterExe config --no-analytics
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter configuration failed with exit code $LASTEXITCODE."
  }
  & $flutterExe --version
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter verification failed with exit code $LASTEXITCODE."
  }
} finally {
  if ($lock) {
    $lock.Dispose()
  }
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
