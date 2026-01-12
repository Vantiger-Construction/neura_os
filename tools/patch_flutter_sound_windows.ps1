param(
  [Parameter(Mandatory = $false)]
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

$pluginWindowsDir = Join-Path $ProjectRoot 'windows\flutter\ephemeral\.plugin_symlinks\flutter_sound\windows'
$taudioCapiCpp = Join-Path $pluginWindowsDir 'taudio_plugin_c_api.cpp'
$shimIncludeDir = Join-Path $pluginWindowsDir 'include\flutter_sound'
$shimHeader = Join-Path $shimIncludeDir 'flutter_sound_plugin_c_api.h'

if (-not (Test-Path -LiteralPath $pluginWindowsDir)) {
  throw "flutter_sound Windows plugin folder not found at: $pluginWindowsDir`nRun 'flutter pub get' first."
}

if (-not (Test-Path -LiteralPath $taudioCapiCpp)) {
  throw "Expected file not found: $taudioCapiCpp"
}

New-Item -ItemType Directory -Force -Path $shimIncludeDir | Out-Null

# Create the header Flutter's generated_plugin_registrant.cc expects.
$headerContent = @'
#ifndef FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// Shim: flutter_sound's Windows sources export TaudioPluginCApiRegisterWithRegistrar.
// Flutter expects FlutterSoundPluginCApiRegisterWithRegistrar.
FLUTTER_PLUGIN_EXPORT void FlutterSoundPluginCApiRegisterWithRegistrar(
  FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_C_API_H_
'@

Set-Content -LiteralPath $shimHeader -Value $headerContent -Encoding UTF8

# Patch the C API .cpp to also export the expected symbol.
$cpp = Get-Content -LiteralPath $taudioCapiCpp -Raw
if ($cpp -notmatch '#define FLUTTER_PLUGIN_IMPL') {
  $cpp = $cpp -replace '#include "include/taudio/taudio_plugin_c_api.h"', '#define FLUTTER_PLUGIN_IMPL`r`n#include "include/taudio/taudio_plugin_c_api.h"'
}

if ($cpp -notmatch 'FlutterSoundPluginCApiRegisterWithRegistrar') {
  $cpp += "`r`n`r`n// Added by tools/patch_flutter_sound_windows.ps1`r`n" +
          'extern "C" __declspec(dllexport) void FlutterSoundPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {' + "`r`n" +
          '  TaudioPluginCApiRegisterWithRegistrar(registrar);' + "`r`n" +
          '}' + "`r`n"
  Set-Content -LiteralPath $taudioCapiCpp -Value $cpp -Encoding UTF8
}

Write-Host "Patched flutter_sound Windows plugin shim OK." -ForegroundColor Green
Write-Host "- Header: $shimHeader"
Write-Host "- Patched: $taudioCapiCpp"
