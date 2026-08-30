#Requires -Version 7.2
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArtifactRoot,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string]$PreviousArtifactRoot,
  [switch]$RequireAuthenticode,
  [string]$ExpectedPublisher
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
  return [IO.Path]::GetRelativePath($Root, $Path).Replace('\\', '/')
}

function Get-PayloadManifest([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse |
    Where-Object { $_.Name -notin @('RELEASE_MANIFEST.json', 'SHA256SUMS.txt') } |
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
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
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

$artifact = Resolve-BoundedDirectory $ArtifactRoot 'ArtifactRoot'
$output = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $output -Force | Out-Null
Assert-WindowsPayload $artifact
if ($RequireAuthenticode) {
  if (-not $IsWindows) { throw 'Authenticode enforcement requires Windows PowerShell.' }
  Assert-Authenticode $artifact
}

$manifestFiles = Get-PayloadManifest $artifact
$manifest = [ordered]@{
  schema = 1
  product = 'Neura Companion'
  createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  sourceCommit = $env:GITHUB_SHA
  signaturePolicy = if ($RequireAuthenticode) { 'required' } else { 'development-not-required' }
  files = $manifestFiles
}
$manifestPath = Join-Path $output 'RELEASE_MANIFEST.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$manifestFiles | ForEach-Object { "$($_.sha256)  $($_.path)" } |
  Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
Assert-Manifest $artifact $manifestFiles

if ($PreviousArtifactRoot) {
  $previous = Resolve-BoundedDirectory $PreviousArtifactRoot 'PreviousArtifactRoot'
  Assert-WindowsPayload $previous
  $rehearsal = Join-Path $output 'upgrade-rehearsal'
  $slotA = Join-Path $rehearsal 'slot-a'
  $slotB = Join-Path $rehearsal 'slot-b'
  if (Test-Path -LiteralPath $rehearsal) {
    Remove-Item -LiteralPath $rehearsal -Recurse -Force
  }
  New-Item -ItemType Directory -Path $slotA, $slotB -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $previous '*') -Destination $slotA -Recurse
  $before = Get-PayloadManifest $slotA
  Copy-Item -LiteralPath (Join-Path $artifact '*') -Destination $slotB -Recurse
  Assert-Manifest $slotB $manifestFiles
  Remove-Item -LiteralPath $slotB -Recurse -Force
  Assert-Manifest $slotA $before
  [ordered]@{
    schema = 1
    upgradeStaged = $true
    stagedPayloadVerified = $true
    rollbackPayloadVerified = $true
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'ROLLBACK_REHEARSAL.json') -Encoding UTF8
}

Write-Host "Release-readiness gates passed: $artifact"
