#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][ValidateSet('windows','android')][string]$Platform,
    [Parameter(Mandatory)][string]$BuildVolume
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:NEURA_CLIENT_CONFIG_SHA256 -or -not $env:NEURA_CLIENT_PROJECT_URL) {
    throw 'Configured-package metadata is absent.'
}
if (-not $env:GITHUB_RUN_ID -or -not $env:GITHUB_RUN_ATTEMPT) {
    throw 'A GitHub run ID and attempt are required for the recovery path.'
}
$runKey = "$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
# Keep recoverable deliverables outside the neura-ci build/cache cleanup tree.
$output = Join-Path $BuildVolume "neura-packages\$Platform\$runKey"
if (Test-Path -LiteralPath $output) { throw 'Recovery package path already exists; refusing to overwrite it.' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$sourceCommit = (& git -C $SourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine the packaged source commit.' }
if ($Platform -eq 'windows') {
    $release = Join-Path $SourceRoot 'build\windows\x64\runner\Release'
    foreach ($required in @('neuro_companion.exe','flutter_windows.dll','data\icudtl.dat','data\flutter_assets')) {
        if (-not (Test-Path -LiteralPath (Join-Path $release $required))) { throw "Missing Windows package member: $required" }
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = Join-Path $output "NeuraCompanion-Windows-configured-$runKey.zip"
    [IO.Compression.ZipFile]::CreateFromDirectory($release, $archive)
} else {
    $verified = Join-Path $SourceRoot 'recovery_downloads\android'
    $apks = @(Get-ChildItem -LiteralPath $verified -Filter '*.apk' -File)
    if ($apks.Count -ne 1 -or $apks[0].Length -eq 0) { throw 'Expected exactly one verified, non-empty Android APK.' }
    Copy-Item -LiteralPath $apks[0].FullName -Destination $output
}
$manifest = [ordered]@{
    source_commit = $sourceCommit
    platform = $Platform
    project_url = $env:NEURA_CLIENT_PROJECT_URL
    config_sha256 = $env:NEURA_CLIENT_CONFIG_SHA256
    run_id = $env:GITHUB_RUN_ID
    run_attempt = $env:GITHUB_RUN_ATTEMPT
    device_qa = 'pending'
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $output 'build-manifest.json') -Encoding UTF8
$checksums = Get-ChildItem -LiteralPath $output -File | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
}
$checksums | Set-Content (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
"package_path=$output" | Out-File $env:GITHUB_OUTPUT -Encoding utf8 -Append
Write-Host "Recoverable configured package: $output"
"Configured $Platform package retained on the runner at: $output" | Out-File $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append

