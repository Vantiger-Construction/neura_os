#Requires -Version 5.1
<#
.SYNOPSIS
Compatibility entrypoint for a verified Neura rebuild with a Windows installer.

.DESCRIPTION
Delegates to tools\Build-Neura-GoogleDriveRebuild.ps1 and enables
-BuildInstaller by default. The legacy -SkipInstaller switch remains available.
All build, validation, smoke-test, packaging, and installer behavior remains
owned by that canonical script.
#>
[CmdletBinding()]
param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$SourceRoot,
    [string]$FlutterPath,
    [string]$InnoSetupPath,
    [string]$BuildName,
    [int]$BuildNumber = 0,
    [switch]$SkipTests,
    [switch]$SkipLaunchSmokeTest,
    [switch]$BuildAndroid,
    [switch]$SkipInstaller,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$builder = Join-Path $PSScriptRoot 'tools\Build-Neura-GoogleDriveRebuild.ps1'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "Canonical Neura rebuild script is missing: $builder"
}

$forwardedParameters = @{}
foreach ($name in $PSBoundParameters.Keys) {
    if ($name -ne 'SkipInstaller') {
        $forwardedParameters[$name] = $PSBoundParameters[$name]
    }
}

if ($SkipInstaller) {
    & $builder @forwardedParameters
} else {
    & $builder @forwardedParameters -BuildInstaller
}
exit $LASTEXITCODE
