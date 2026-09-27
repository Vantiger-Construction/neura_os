#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Literal {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Literal,
        [Parameter(Mandatory)][string]$Failure
    )

    if (-not $Text.Contains($Literal)) {
        throw $Failure
    }
}

$Root = (Resolve-Path -LiteralPath $Root).Path
$runnerRoot = Join-Path $Root 'windows\runner'
$sourcePath = Join-Path $runnerRoot 'neura_on_device_asr.cpp'
$headerPath = Join-Path $runnerRoot 'neura_on_device_asr.h'
$cmakePath = Join-Path $runnerRoot 'CMakeLists.txt'
$windowPath = Join-Path $runnerRoot 'flutter_window.cpp'
$dartPath = Join-Path $Root 'lib\services\neura_onnx_int4_speech_engine.dart'

foreach ($requiredPath in @(
    $sourcePath,
    $headerPath,
    $cmakePath,
    $windowPath,
    $dartPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Windows on-device ASR contract file is missing: $requiredPath"
    }
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw
$cmake = Get-Content -LiteralPath $cmakePath -Raw
$window = Get-Content -LiteralPath $windowPath -Raw
$dart = Get-Content -LiteralPath $dartPath -Raw

if ($cmake -notmatch '(?s)option\s*\(\s*NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR.*?\sOFF\s*\)') {
    throw 'The native ONNX backend must remain disabled in default builds.'
}
Require-Literal $source 'NEURA_ON_DEVICE_ASR_ENABLE' `
    'The backend is missing its separate runtime opt-in.'
Require-Literal $source 'NEURA_ON_DEVICE_ASR_MODEL_DIR' `
    'The backend is missing its explicit local model directory.'
Require-Literal $source 'DRIVE_REMOTE' `
    'Remote-drive model paths are not rejected.'
Require-Literal $source 'L"://"' `
    'URL-shaped model paths are not rejected.'

foreach ($modelFile in @(
    'encoder.int4.onnx',
    'decoder.int4.onnx',
    'joiner.int4.onnx',
    'tokens.txt'
)) {
    Require-Literal $source $modelFile `
        "The explicit model contract is missing $modelFile."
}

$combinedNative = $source + "`n" + $cmake
$networkOrDownloadPattern = @(
    '\bWinHttpOpen\b',
    '\bInternetOpen(?:A|W)?\b',
    '\bURLDownloadToFile(?:A|W)?\b',
    '\bWSAStartup\b',
    '\bcurl_easy_init\b',
    'file\s*\(\s*DOWNLOAD',
    'FetchContent_Declare\s*\([^)]*(?:sherpa|portaudio)'
) -join '|'
if ($combinedNative -match $networkOrDownloadPattern) {
    throw 'The Windows ONNX backend contains a network or dependency-download path.'
}

foreach ($method in @('isAvailable', 'start', 'stop', 'onSegment')) {
    Require-Literal $source ('"' + $method + '"') `
        "The native channel is missing $method behavior."
}
Require-Literal $source 'Pa_StopStream(audio_stream_)' `
    'Stop does not synchronously stop microphone capture.'
Require-Literal $source 'Pa_CloseStream(audio_stream_)' `
    'Stop does not close the microphone stream.'
Require-Literal $source 'decoder_thread_.join()' `
    'Stop does not join the local decoder worker.'
Require-Literal $source 'ClearPendingSegments();' `
    'Stop does not discard late native transcript segments.'
Require-Literal $window 'on_device_asr_.reset();' `
    'Window teardown does not synchronously destroy the ONNX channel owner.'
Require-Literal $header 'kDrainMessage' `
    'Native segments are not marshalled back to the Flutter window thread.'
Require-Literal $dart 'experimental: true' `
    'The ONNX engine must remain outside default production selection.'

Write-Host 'Windows on-device ASR offline/lifecycle contract passed.' -ForegroundColor Green
