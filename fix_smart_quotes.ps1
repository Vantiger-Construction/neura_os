# fix_smart_quotes.ps1  —  PHASE 1: kill the smart-quote / apostrophe corruption
# Run from the Flutter project root (the folder containing pubspec.yaml):
#   cd C:\neura_os   (or D:\Vantiger1\neura_os)
#   powershell -ExecutionPolicy Bypass -File .\fix_smart_quotes.ps1
#   flutter analyze

$ErrorActionPreference = 'Stop'

$rootDir = Get-Location
$lib = Join-Path $rootDir 'lib'
if (-not (Test-Path $lib)) {
    throw "No 'lib' folder here. cd into the Flutter project root (where pubspec.yaml lives) and re-run."
}

# Timestamped backup so nothing is lost
$backup = Join-Path $rootDir ("_quote_backup_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup | Out-Null

# Curly / typographic chars  ->  plain ASCII
$map = @{
    ([char]0x2018) = "'"   # left single  '
    ([char]0x2019) = "'"   # right single '  (the usual apostrophe culprit)
    ([char]0x201A) = "'"   # single low-9 ‚
    ([char]0x2032) = "'"   # prime        ′
    ([char]0x201C) = '"'   # left double  "
    ([char]0x201D) = '"'   # right double "
    ([char]0x201E) = '"'   # double low-9 „
    ([char]0x2033) = '"'   # double prime ″
}

$changed = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Get-ChildItem -Path $lib -Recurse -Filter *.dart | ForEach-Object {
    $path = $_.FullName
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $orig = $text
    foreach ($k in $map.Keys) { $text = $text.Replace($k, $map[$k]) }

    if ($text -ne $orig) {
        $rel  = $path.Substring($rootDir.Path.Length).TrimStart('\')
        $dest = Join-Path $backup $rel
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Copy-Item $path $dest
        [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
        Write-Host ("fixed:  " + $rel)
        $changed++
    }
}

Write-Host ""
Write-Host ("Files changed: " + $changed)
Write-Host ("Backups in:    " + $backup)
Write-Host ""
Write-Host "NEXT: run  flutter analyze"
Write-Host "If a few 'unterminated_string_literal' errors remain, those are single-quoted"
Write-Host "strings that contain an apostrophe (e.g. 'don''t'). Fix by switching that one"
Write-Host "string's delimiters from '...' to \"...\". There will be only a handful."
