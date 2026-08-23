#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-NeuraRoot {
    param([string]$Start)

    if (-not [string]::IsNullOrWhiteSpace($Start)) {
        $candidate = (Resolve-Path -LiteralPath $Start).Path
    } else {
        $candidate = (Get-Location).Path
    }

    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'pubspec.yaml') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate '.git') -PathType Container)) {
            return $candidate
        }

        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
            throw "Could not find a Neura Git root above: $Start"
        }
        $candidate = $parent
    }
}

$root = Find-NeuraRoot -Start $RepoRoot
$payloadRoot = Join-Path $PSScriptRoot 'resolved'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $root ".neura_merge_backup\$stamp"

$relativeFiles = @(
    'android\gradle\wrapper\gradle-wrapper.properties',
    'lib\core\neura_fault_system.dart',
    'lib\modules\core\error_handler.dart',
    'lib\services\neura_tts_service.dart',
    'windows\runner\flutter_window.cpp'
)

Write-Host "Neura root: $root" -ForegroundColor Cyan
Write-Host "Backup:     $backupRoot" -ForegroundColor Cyan

foreach ($relative in $relativeFiles) {
    $source = Join-Path $payloadRoot $relative
    $target = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Resolver payload is missing: $source"
    }

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $backup = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force |
            Out-Null
        Copy-Item -LiteralPath $target -Destination $backup -Force
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force |
        Out-Null
    $content = [IO.File]::ReadAllText($source)
    [IO.File]::WriteAllText(
        $target,
        $content,
        [Text.UTF8Encoding]::new($false)
    )
    Write-Host "Resolved $relative" -ForegroundColor Green
}

Push-Location $root
try {
    $dartFiles = @(
        'lib/core/neura_fault_system.dart',
        'lib/modules/core/error_handler.dart',
        'lib/services/neura_tts_service.dart'
    )

    if (Get-Command dart -ErrorAction SilentlyContinue) {
        & dart format @dartFiles
        if ($LASTEXITCODE -ne 0) {
            throw "dart format failed with exit code $LASTEXITCODE"
        }
    }

    $markerMatches = Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/](\.git|build|\.dart_tool|\.gradle)[\\/]'
        } |
        Select-String -Pattern '^(<<<<<<<|=======|>>>>>>>)' -ErrorAction SilentlyContinue

    if ($markerMatches) {
        $markerMatches |
            ForEach-Object {
                Write-Host "$($_.Path):$($_.LineNumber): $($_.Line)" `
                    -ForegroundColor Red
            }
        throw 'Merge-conflict markers remain in the repository.'
    }

    if (-not $SkipValidation) {
        if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
            throw 'Flutter is not on PATH. Re-run with -SkipValidation or install Flutter.'
        }

        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get failed with exit code $LASTEXITCODE"
        }

        & flutter analyze --fatal-infos
        if ($LASTEXITCODE -ne 0) {
            throw "flutter analyze failed with exit code $LASTEXITCODE"
        }

        & flutter test --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "flutter test failed with exit code $LASTEXITCODE"
        }
    }

    Write-Host ''
    Write-Host 'Merge resolution completed successfully.' -ForegroundColor Green
    Write-Host 'Review git diff, then commit the five resolved files.' -ForegroundColor Cyan
}
finally {
    Pop-Location
}
