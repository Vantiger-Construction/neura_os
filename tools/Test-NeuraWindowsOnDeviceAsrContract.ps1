#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [switch]$RunNativeHarness
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
$sessionPath = Join-Path $runnerRoot 'neura_asr_session.h'
$headerPath = Join-Path $runnerRoot 'neura_on_device_asr.h'
$cmakePath = Join-Path $runnerRoot 'CMakeLists.txt'
$windowPath = Join-Path $runnerRoot 'flutter_window.cpp'
$dartPath = Join-Path $Root 'lib\services\neura_onnx_int4_speech_engine.dart'

foreach ($requiredPath in @(
    $sourcePath,
    $sessionPath,
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
$session = Get-Content -LiteralPath $sessionPath -Raw
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

$combinedNative = $source + "`n" + $session + "`n" + $cmake
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
Require-Literal $session 'worker_.join()' `
    'Stop does not join the local decoder worker.'
Require-Literal $source 'ClearPendingSegments();' `
    'Stop does not discard late native transcript segments.'
Require-Literal $window 'on_device_asr_.reset();' `
    'Window teardown does not synchronously destroy the ONNX channel owner.'
Require-Literal $header 'kDrainMessage' `
    'Native segments are not marshalled back to the Flutter window thread.'
Require-Literal $dart 'experimental: true' `
    'The ONNX engine must remain outside default production selection.'

Require-Literal $source 'IsPlainLocalPath' `
    'Model paths must reject reparse points before opening model files.'
Require-Literal $session 'kCapacity = 32000' `
    'Audio handoff must remain bounded.'

Write-Host 'Windows on-device ASR source contract passed.' -ForegroundColor Green

if ($RunNativeHarness) {
    $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    $cmakeExe = if ($cmakeCommand) { $cmakeCommand.Source } else { $null }
    if (-not $cmakeExe) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} `
            'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
            $cmakeExe = & $vswhere -latest -products * -find `
                'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' |
                Select-Object -First 1
        }
    }
    if ([string]::IsNullOrWhiteSpace($cmakeExe)) {
        throw 'The native ASR harness requires the existing Windows CMake/C++ toolchain.'
    }
    $ctestExe = Join-Path (Split-Path -Parent $cmakeExe) 'ctest.exe'
    if (-not (Test-Path -LiteralPath $ctestExe -PathType Leaf)) {
        throw 'ctest.exe is missing from the existing CMake toolchain.'
    }
    $harnessSource = Join-Path $Root 'tools\asr_harness'
    $harnessBuild = Join-Path $Root ('build\asr-harness-' + [Guid]::NewGuid().ToString('N'))
    try {
        & $cmakeExe -S $harnessSource -B $harnessBuild
        if ($LASTEXITCODE -ne 0) { throw 'Native ASR harness configuration failed.' }
        & $cmakeExe --build $harnessBuild --config Release
        if ($LASTEXITCODE -ne 0) { throw 'Native ASR harness compilation failed.' }
        & $ctestExe --test-dir $harnessBuild -C Release --output-on-failure --timeout 30
        if ($LASTEXITCODE -ne 0) { throw 'Native ASR lifecycle regression failed.' }
    } finally {
        if (Test-Path -LiteralPath $harnessBuild) {
            Remove-Item -LiteralPath $harnessBuild -Recurse -Force
        }
    }
}
