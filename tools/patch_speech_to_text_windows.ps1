param(
  [Parameter(Mandatory = $false)]
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

$headerPath = Join-Path $ProjectRoot 'windows\flutter\ephemeral\.plugin_symlinks\speech_to_text_windows\windows\include\speech_to_text_windows\speech_to_text_windows.h'

if (-not (Test-Path -LiteralPath $headerPath)) {
  throw "speech_to_text_windows header not found at: $headerPath`nRun 'flutter pub get' first."
}

$text = Get-Content -LiteralPath $headerPath -Raw

# Fix broken include guard (some published versions incorrectly reuse local_auth's guard).
$text = $text -replace 'FLUTTER_PLUGIN_LOCAL_AUTH_WINDOWS_PLUGIN_H_', 'FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_H_'

# Also fix the trailing comment if present.
$text = $text -replace 'endif\s*//\s*FLUTTER_PLUGIN_LOCAL_AUTH_WINDOWS_PLUGIN_H_', 'endif  // FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_H_'

Set-Content -LiteralPath $headerPath -Value $text -Encoding UTF8

Write-Host "Patched speech_to_text_windows header guard OK." -ForegroundColor Green
Write-Host "- Header: $headerPath"
