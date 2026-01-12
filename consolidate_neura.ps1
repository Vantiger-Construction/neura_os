# Neura Companion Consolidation Script
# This script will extract all Neura zip files and consolidate them

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Destination folder
$destFolder = "$env:USERPROFILE\Desktop\Neura Companion ver. 1.0.0.0"
$tempExtractRoot = "$env:TEMP\NeuraConsolidation"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Neura Companion Consolidation Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create destination and temp folders
Write-Host "[1/5] Creating folders..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
New-Item -ItemType Directory -Force -Path $tempExtractRoot | Out-Null
Write-Host "  ✓ Created: $destFolder" -ForegroundColor Green
Write-Host "  ✓ Created temp: $tempExtractRoot" -ForegroundColor Green

# Find all Neura zip files
Write-Host "`n[2/5] Searching for Neura zip files..." -ForegroundColor Yellow
$zipFiles = @()
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }

foreach ($drive in $drives) {
    Write-Host "  Scanning $($drive.Root)..." -ForegroundColor Gray
    try {
        $found = Get-ChildItem -Path $drive.Root -Filter "*neura*.zip" -Recurse -ErrorAction SilentlyContinue -File
        $zipFiles += $found
        Write-Host "    Found $($found.Count) files" -ForegroundColor Gray
    } catch {
        Write-Host "    Skipped (access denied or error)" -ForegroundColor DarkGray
    }
}

Write-Host "  ✓ Total found: $($zipFiles.Count) zip files" -ForegroundColor Green

# Extract all zips
Write-Host "`n[3/5] Extracting zip files..." -ForegroundColor Yellow
$extracted = 0
$failed = 0

foreach ($zip in $zipFiles) {
    $extracted++
    $percent = [math]::Round(($extracted / $zipFiles.Count) * 100, 1)
    
    if ($extracted % 100 -eq 0 -or $extracted -eq $zipFiles.Count) {
        Write-Host "  Progress: $extracted/$($zipFiles.Count) ($percent%)" -ForegroundColor Gray
    }
    
    try {
        $extractPath = Join-Path $tempExtractRoot "Extract_$extracted"
        Expand-Archive -Path $zip.FullName -DestinationPath $extractPath -Force -ErrorAction Stop
    } catch {
        $failed++
    }
}

Write-Host "  ✓ Extracted: $extracted files ($failed failed)" -ForegroundColor Green

# Copy workspace folders
Write-Host "`n[4/5] Consolidating workspace folders..." -ForegroundColor Yellow
$workspaceFolders = Get-ChildItem -Path "C:\neura" -Directory -Filter "*Neura*" -ErrorAction SilentlyContinue

foreach ($folder in $workspaceFolders) {
    Write-Host "  Copying $($folder.Name)..." -ForegroundColor Gray
    $destPath = Join-Path $destFolder $folder.Name
    
    try {
        Copy-Item -Path $folder.FullName -Destination $destPath -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "    Warning: Some files skipped" -ForegroundColor DarkYellow
    }
}

# Merge extracted content
Write-Host "`n  Merging extracted content..." -ForegroundColor Gray
$extractedFolders = Get-ChildItem -Path $tempExtractRoot -Directory -ErrorAction SilentlyContinue

foreach ($extractFolder in $extractedFolders) {
    try {
        $items = Get-ChildItem -Path $extractFolder.FullName -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            $destPath = Join-Path $destFolder $item.Name
            if (Test-Path $destPath) {
                # Merge if exists
                Copy-Item -Path $item.FullName -Destination $destFolder -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                # Copy if new
                Copy-Item -Path $item.FullName -Destination $destFolder -Recurse -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # Continue on error
    }
}

Write-Host "  ✓ Consolidation complete" -ForegroundColor Green

# Cleanup
Write-Host "`n[5/5] Cleaning up temporary files..." -ForegroundColor Yellow
try {
    Remove-Item -Path $tempExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Cleanup complete" -ForegroundColor Green
} catch {
    Write-Host "  ! Temp files remain at: $tempExtractRoot" -ForegroundColor DarkYellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CONSOLIDATION COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Location: $destFolder" -ForegroundColor White
Write-Host "`nProcessed:" -ForegroundColor White
Write-Host "  - $($zipFiles.Count) zip files extracted" -ForegroundColor White
Write-Host "  - $($workspaceFolders.Count) workspace folders copied" -ForegroundColor White
Write-Host ""

# Open destination folder
explorer $destFolder
