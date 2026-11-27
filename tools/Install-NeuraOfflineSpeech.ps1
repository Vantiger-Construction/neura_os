#Requires -Version 5.1
<#
.SYNOPSIS
Sets up Neura's offline streaming speech recognizer (Sherpa-ONNX) on this PC.

.DESCRIPTION
Neura never downloads a model by itself. This script is the explicit,
person-run step that does it, once, and only when -AcceptModelLicense is given:

  1. Downloads the pinned Sherpa-ONNX Windows x64 shared SDK and the chosen
     model from the k2-fsa GitHub releases: the English streaming Zipformer
     (-Model English, the default) or multilingual Whisper with the Silero
     voice-activity model (-Model MultilingualBase or MultilingualSmall),
     which hears and identifies English, Spanish, Italian, German and French.
  2. Verifies each archive against -SdkSha256 / -ModelSha256 when given;
     otherwise prints the hashes so you can record and pin them.
  3. Copies the four model files into -ModelDir and writes
     neura-asr-manifest.json (profile, file SHA-256 values, license evidence,
     networkRequired: false), the format NeuraOnDeviceAsrPackageManifest checks.
  4. With -SetEnvironment, sets the three user environment variables that opt
     Neura in (NEURA_ON_DEVICE_ASR_ENABLE=1, the model dir and the profile).
  5. With -Build, reconfigures and builds the Windows app with
     NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR=ON and copies the runtime DLLs next to
     the built executable.

PortAudio has no official Windows binary. Pass -PortAudioRoot (a directory
holding include\portaudio.h and lib\portaudio.lib), or install it with
`vcpkg install portaudio:x64-windows` and pass -VcpkgRoot.

To turn offline recognition off again: run with -Disable, or remove the
NEURA_ON_DEVICE_ASR_ENABLE user environment variable. Neura then uses the
built-in Windows (SAPI) recognizer as before.

.EXAMPLE
.\tools\Install-NeuraOfflineSpeech.ps1 -AcceptModelLicense -SetEnvironment `
  -VcpkgRoot C:\vcpkg -Build

.EXAMPLE
# English, Spanish, Italian, German and French, detected per phrase.
.\tools\Install-NeuraOfflineSpeech.ps1 -Model MultilingualBase `
  -AcceptModelLicense -SetEnvironment -VcpkgRoot C:\vcpkg -Build
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [switch]$AcceptModelLicense,

    [Parameter(ParameterSetName = 'Install')]
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Neura\OfflineSpeech'),

    [Parameter(ParameterSetName = 'Install')]
    [string]$SherpaVersion = '1.12.14',

    [Parameter(ParameterSetName = 'Install')]
    [string]$SdkSha256 = '',

    [Parameter(ParameterSetName = 'Install')]
    [string]$ModelSha256 = '',

    # English: streaming English Zipformer (about 200 MB, fastest).
    # MultilingualBase / MultilingualSmall: Whisper base (about 200 MB) or
    # small (about 600 MB, more accurate, slower) plus Silero VAD.
    [Parameter(ParameterSetName = 'Install')]
    [ValidateSet('English', 'MultilingualBase', 'MultilingualSmall')]
    [string]$Model = 'English',

    [Parameter(ParameterSetName = 'Install')]
    [string]$VadSha256 = '',

    [Parameter(ParameterSetName = 'Install')]
    [string]$PortAudioRoot = '',

    [Parameter(ParameterSetName = 'Install')]
    [string]$VcpkgRoot = '',

    [Parameter(ParameterSetName = 'Install')]
    [switch]$SetEnvironment,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Build,

    [Parameter(ParameterSetName = 'Install')]
    [ValidateSet('Debug', 'Profile', 'Release')]
    [string]$Configuration = 'Release',

    [Parameter(ParameterSetName = 'Install')]
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [Parameter(ParameterSetName = 'Disable', Mandatory)]
    [switch]$Disable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$needsVad = $false
switch ($Model) {
    'English' {
        $profileId = 'zipformer-en-2023-06-26-int8'
        $modelArchiveName = 'sherpa-onnx-streaming-zipformer-en-2023-06-26'
        $modelFiles = @(
            'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
            'decoder-epoch-99-avg-1-chunk-16-left-128.onnx',
            'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
            'tokens.txt'
        )
        $modelDocsUrl = 'https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html'
        $modelSize = 'about 200 MB'
    }
    default {
        $size = if ($Model -eq 'MultilingualSmall') { 'small' } else { 'base' }
        $profileId = "whisper-$size-int8"
        $modelArchiveName = "sherpa-onnx-whisper-$size"
        $modelFiles = @(
            "$size-encoder.int8.onnx",
            "$size-decoder.int8.onnx",
            "$size-tokens.txt"
        )
        $needsVad = $true
        $modelDocsUrl = 'https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/index.html'
        $modelSize = if ($size -eq 'small') { 'about 600 MB' } else { 'about 200 MB' }
    }
}
$vadFile = 'silero_vad.onnx'
$vadUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$vadFile"
$licenseUrl = 'https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE'

function Set-UserVariable([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "Env:$Name" -Value $Value
}

if ($Disable) {
    foreach ($name in 'NEURA_ON_DEVICE_ASR_ENABLE',
                      'NEURA_ON_DEVICE_ASR_MODEL_DIR',
                      'NEURA_ON_DEVICE_ASR_MODEL_PROFILE') {
        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
    Write-Host 'Offline streaming recognition is off. Restart Neura; it will use the Windows recognizer.'
    return
}

if (-not $AcceptModelLicense) {
    Write-Host "This downloads the Sherpa-ONNX SDK and the $Model speech model ($modelSize)."
    if ($needsVad) {
        Write-Host 'Whisper models are released by OpenAI under the MIT license; Silero VAD under the MIT license.'
    }
    Write-Host "Review the licenses first: $licenseUrl"
    Write-Host "Model documentation: $modelDocsUrl"
    Write-Host 'Re-run with -AcceptModelLicense to continue. Nothing was downloaded.'
    exit 2
}

function Get-VerifiedArchive {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$ExpectedSha256
    )
    if (-not (Test-Path -LiteralPath $Destination)) {
        Write-Host "Downloading $Url"
        $partial = "$Destination.partial"
        Invoke-WebRequest -Uri $Url -OutFile $partial -UseBasicParsing
        Move-Item -LiteralPath $partial -Destination $Destination -Force
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedSha256) {
        if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $Destination -Force
            throw "SHA-256 mismatch for $(Split-Path -Leaf $Destination). Expected $ExpectedSha256, got $actual. The file was deleted."
        }
        Write-Host "Verified $(Split-Path -Leaf $Destination)"
    } else {
        Write-Warning "No pinned hash given for $(Split-Path -Leaf $Destination). SHA-256: $actual"
        Write-Warning 'Record it and pass it next time (-SdkSha256 / -ModelSha256) to pin this download.'
    }
    return $actual
}

function Expand-TarBz2([string]$Archive, [string]$Into) {
    New-Item -ItemType Directory -Force -Path $Into | Out-Null
    # Windows 10 1803+ ships bsdtar as tar.exe, which reads .tar.bz2.
    & tar.exe -xjf $Archive -C $Into
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $Archive" }
}

function Find-One([string]$Under, [string]$Filter) {
    $found = @(Get-ChildItem -LiteralPath $Under -Recurse -File -Filter $Filter)
    if ($found.Count -eq 0) { throw "Could not find $Filter under $Under" }
    return $found[0]
}

$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if ($InstallRoot.StartsWith('\\')) { throw 'Install the model on a local drive, not a network path.' }
$downloads = Join-Path $InstallRoot 'downloads'
$sdkRoot = Join-Path $InstallRoot "sherpa-onnx-$SherpaVersion"
$ModelDir = Join-Path $InstallRoot $profileId
New-Item -ItemType Directory -Force -Path $downloads, $ModelDir | Out-Null

# --- 1. Sherpa-ONNX SDK -----------------------------------------------------
$sdkName = "sherpa-onnx-v$SherpaVersion-win-x64-shared.tar.bz2"
$sdkUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$SherpaVersion/$sdkName"
$sdkHash = Get-VerifiedArchive -Url $sdkUrl -Destination (Join-Path $downloads $sdkName) -ExpectedSha256 $SdkSha256
if (-not (Test-Path -LiteralPath $sdkRoot)) {
    Expand-TarBz2 (Join-Path $downloads $sdkName) $sdkRoot
}
$sherpaHeader = Find-One $sdkRoot 'c-api.h'
$sherpaInclude = $sherpaHeader.Directory.Parent.Parent.FullName
$sherpaLib = (Find-One $sdkRoot 'sherpa-onnx-c-api.lib').FullName
$sherpaDlls = @(Get-ChildItem -LiteralPath $sdkRoot -Recurse -File -Filter '*.dll')

# --- 2. Model ---------------------------------------------------------------
$modelName = "$modelArchiveName.tar.bz2"
$modelUrl = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$modelName"
$modelHash = Get-VerifiedArchive -Url $modelUrl -Destination (Join-Path $downloads $modelName) -ExpectedSha256 $ModelSha256
$modelExtract = Join-Path $downloads $modelArchiveName
if (-not (Test-Path -LiteralPath $modelExtract)) {
    Expand-TarBz2 (Join-Path $downloads $modelName) $downloads
}
$fileHashes = [ordered]@{}
foreach ($file in $modelFiles) {
    $source = Find-One $modelExtract $file
    $target = Join-Path $ModelDir $file
    Copy-Item -LiteralPath $source.FullName -Destination $target -Force
    $fileHashes[$file] = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
}
$vadEvidence = ''
if ($needsVad) {
    # Silero VAD splits live audio into phrases for the whole-phrase model.
    $vadDownload = Join-Path $downloads $vadFile
    $vadHash = Get-VerifiedArchive -Url $vadUrl -Destination $vadDownload -ExpectedSha256 $VadSha256
    $target = Join-Path $ModelDir $vadFile
    Copy-Item -LiteralPath $vadDownload -Destination $target -Force
    $fileHashes[$vadFile] = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    $vadEvidence = " Voice activity model from $vadUrl (SHA-256 $vadHash)."
}

$manifest = [ordered]@{
    profileId = $profileId
    fileSha256 = $fileHashes
    licenseEvidence = "Downloaded from $modelUrl (archive SHA-256 $modelHash) with SDK $sdkUrl (SHA-256 $sdkHash).$vadEvidence License accepted by the person running Install-NeuraOfflineSpeech.ps1 on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')); see $licenseUrl."
    networkRequired = $false
    createdAtUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ModelDir 'neura-asr-manifest.json') -Encoding UTF8
Write-Host "Model ready in $ModelDir"

# --- 3. Opt in --------------------------------------------------------------
if ($SetEnvironment) {
    Set-UserVariable 'NEURA_ON_DEVICE_ASR_ENABLE' '1'
    Set-UserVariable 'NEURA_ON_DEVICE_ASR_MODEL_DIR' $ModelDir
    Set-UserVariable 'NEURA_ON_DEVICE_ASR_MODEL_PROFILE' $profileId
    Write-Host 'Offline streaming recognition is opted in for your Windows user.'
} else {
    Write-Host 'Not opted in yet. Re-run with -SetEnvironment, or set:'
    Write-Host "  NEURA_ON_DEVICE_ASR_ENABLE=1"
    Write-Host "  NEURA_ON_DEVICE_ASR_MODEL_DIR=$ModelDir"
    Write-Host "  NEURA_ON_DEVICE_ASR_MODEL_PROFILE=$profileId"
}

# --- 4. PortAudio and build -------------------------------------------------
if (-not $PortAudioRoot -and $VcpkgRoot) {
    $vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
    if (-not (Test-Path -LiteralPath $vcpkg)) { throw "vcpkg.exe not found in $VcpkgRoot" }
    & $vcpkg install 'portaudio:x64-windows'
    if ($LASTEXITCODE -ne 0) { throw 'vcpkg could not install PortAudio.' }
    $PortAudioRoot = Join-Path $VcpkgRoot 'installed\x64-windows'
}

if (-not $Build) {
    Write-Host ''
    Write-Host 'To build Neura with the offline recognizer, re-run with -Build (and -PortAudioRoot or -VcpkgRoot).'
    return
}
if (-not $PortAudioRoot) { throw 'Building needs PortAudio: pass -PortAudioRoot or -VcpkgRoot.' }
$portAudioHeader = Join-Path $PortAudioRoot 'include\portaudio.h'
$portAudioLib = Join-Path $PortAudioRoot 'lib\portaudio.lib'
foreach ($path in $portAudioHeader, $portAudioLib) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing $path" }
}

Push-Location $Root
try {
    & flutter build windows "--$($Configuration.ToLowerInvariant())"
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
    $buildDir = Join-Path $Root 'build\windows\x64'
    & cmake -S (Join-Path $Root 'windows') -B $buildDir `
        -DNEURA_ENABLE_WINDOWS_ON_DEVICE_ASR=ON `
        "-DNEURA_SHERPA_ONNX_INCLUDE_DIR=$($sherpaInclude -replace '\\', '/')" `
        "-DNEURA_SHERPA_ONNX_LIBRARY=$($sherpaLib -replace '\\', '/')" `
        "-DNEURA_PORTAUDIO_INCLUDE_DIR=$((Join-Path $PortAudioRoot 'include') -replace '\\', '/')" `
        "-DNEURA_PORTAUDIO_LIBRARY=$($portAudioLib -replace '\\', '/')"
    if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed.' }
    & cmake --build $buildDir --config $Configuration
    if ($LASTEXITCODE -ne 0) { throw 'CMake build failed.' }

    $exeDir = Join-Path $buildDir "runner\$Configuration"
    $portAudioDlls = @(Get-ChildItem -LiteralPath (Join-Path $PortAudioRoot 'bin') -Filter 'portaudio*.dll' -ErrorAction SilentlyContinue)
    foreach ($dll in $sherpaDlls + $portAudioDlls) {
        Copy-Item -LiteralPath $dll.FullName -Destination $exeDir -Force
    }
    Write-Host "Built with offline recognition: $exeDir"
    Write-Host 'Start Neura from there, open chat and tap the microphone.'
    if ($needsVad) {
        Write-Host 'Speak English, Spanish, Italian, German or French; Neura replies in the language she hears.'
    }
} finally {
    Pop-Location
}
