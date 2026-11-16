#Requires -Version 7.2
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArtifactRoot,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string]$PreviousArtifactRoot,
  [switch]$RequireAuthenticode,
  [string]$ExpectedPublisher,
  [string]$LatestTag = $env:NEURA_RELEASE_TAG,
  [string]$HtmlUrl = $env:NEURA_RELEASE_HTML_URL
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-BoundedDirectory([string]$Path, [string]$Name) {
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    throw "$Name is not a directory: $resolved"
  }
  return $resolved
}

function Get-RelativePath([string]$Root, [string]$Path) {
  return [IO.Path]::GetRelativePath($Root, $Path).Replace([IO.Path]::DirectorySeparatorChar, '/')
}

function Get-PayloadManifest([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force |
    Sort-Object FullName)
  if ($files.Count -eq 0) { throw "Artifact payload is empty: $Root" }

  return @($files | ForEach-Object {
    [ordered]@{
      path = Get-RelativePath -Root $Root -Path $_.FullName
      bytes = $_.Length
      sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  })
}

function Assert-WindowsPayload([string]$Root) {
  $exe = Join-Path $Root 'neuro_companion.exe'
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or (Get-Item -LiteralPath $exe).Length -le 0) {
    throw "Required executable is missing: $exe"
  }
  foreach ($relative in @('flutter_windows.dll', 'data/icudtl.dat', 'data/app.so')) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -le 0) {
      throw "Required release payload is missing or empty: $relative"
    }
  }
}

function Assert-Authenticode([string]$Root) {
  foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse |
      Where-Object { $_.Extension -in @('.exe', '.dll') }) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid') {
      throw "Invalid Authenticode signature ($($signature.Status)): $(Get-RelativePath $Root $file.FullName)"
    }
    if ($ExpectedPublisher -and
        $signature.SignerCertificate.Subject -notlike "*$ExpectedPublisher*") {
      throw "Unexpected signer for $(Get-RelativePath $Root $file.FullName)"
    }
  }
}

function Assert-Manifest([string]$Root, [object[]]$Expected) {
  $actual = Get-PayloadManifest -Root $Root
  $actualJson = $actual | ConvertTo-Json -Depth 5 -Compress
  $expectedJson = $Expected | ConvertTo-Json -Depth 5 -Compress
  if ($actualJson -cne $expectedJson) { throw "Artifact verification failed for $Root" }
}

function Get-TextSha256([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
  } finally {
    $sha.Dispose()
  }
}

$artifact = Resolve-BoundedDirectory $ArtifactRoot 'ArtifactRoot'
$output = [IO.Path]::GetFullPath($OutputRoot)
# Receipts from another invocation must never be mistaken for this result.
if ((Test-Path -LiteralPath $output) -and @(Get-ChildItem -LiteralPath $output -Force).Count) {
  throw "OutputRoot must be a fresh or empty evidence directory: $output"
}
Assert-WindowsPayload $artifact
if ($RequireAuthenticode) {
  if (-not $IsWindows) { throw 'Authenticode enforcement requires Windows PowerShell.' }
  Assert-Authenticode $artifact
}

$manifestFiles = Get-PayloadManifest $artifact
$payloadDigestJson = $manifestFiles | ConvertTo-Json -Depth 8 -Compress
if ([string]::IsNullOrWhiteSpace($LatestTag) -xor [string]::IsNullOrWhiteSpace($HtmlUrl)) {
  throw 'LatestTag and HtmlUrl must be supplied together for a public update manifest.'
}
$manifest = [ordered]@{
  schema = 1
  product = 'Neura Companion'
  createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  sourceCommit = $env:GITHUB_SHA
  signaturePolicy = if ($RequireAuthenticode) { 'required' } else { 'development-not-required' }
  userInitiatedInstallOnly = $true
  files = $manifestFiles
}
if (-not [string]::IsNullOrWhiteSpace($LatestTag)) {
  $manifest['latestTag'] = $LatestTag
  $manifest['htmlUrl'] = $HtmlUrl
  $manifest['artifactSha256'] = Get-TextSha256 $payloadDigestJson
}
if ($PreviousArtifactRoot) {
  $previous = Resolve-BoundedDirectory $PreviousArtifactRoot 'PreviousArtifactRoot'
  Assert-WindowsPayload $previous
  $previousFiles = Get-PayloadManifest $previous
  $previousDigest = Get-TextSha256 ($previousFiles | ConvertTo-Json -Depth 8 -Compress)
  $currentDigest = Get-TextSha256 $payloadDigestJson
  if ($currentDigest -eq $previousDigest) {
    throw 'Rollback rehearsal requires two different payloads.'
  }
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
$manifestPath = Join-Path $output 'RELEASE_MANIFEST.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$manifestFiles | ForEach-Object { "$($_.sha256)  $($_.path)" } |
  Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
Assert-Manifest $artifact $manifestFiles

if ($PreviousArtifactRoot) {
  $rehearsal = Join-Path ([IO.Path]::GetTempPath()) ("neura-slots-" + [guid]::NewGuid())
  $slotA = Join-Path $rehearsal 'slot-a'
  $slotB = Join-Path $rehearsal 'slot-b'
  New-Item -ItemType Directory -Path $rehearsal | Out-Null
  try {
    Copy-Item -LiteralPath $previous -Destination $slotA -Recurse -Force
    Assert-Manifest $slotA $previousFiles
    Copy-Item -LiteralPath $artifact -Destination $slotB -Recurse -Force
    Assert-Manifest $slotB $manifestFiles
    Remove-Item -LiteralPath $slotB -Recurse -Force
    Assert-Manifest $slotA $previousFiles
  } finally {
    Remove-Item -LiteralPath $rehearsal -Recurse -Force
  }
  [ordered]@{
    schema = 1
    previousPayloadSha256 = $previousDigest
    candidatePayloadSha256 = $currentDigest
    upgradeStaged = $true
    stagedPayloadVerified = $true
    rollbackPayloadVerified = $true
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'ROLLBACK_REHEARSAL.json') -Encoding UTF8
}

Write-Host "Release-readiness gates passed: $artifact"
