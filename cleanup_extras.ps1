# Cleanup script - Remove redundant Neura folders and organize files

$redundantFolders = @(
    "C:\neura \neura_companion_full_project_bundle_20251127_055131",
    "C:\neura \Neura_Companion_OS_Legacy_FinalMessages",
    "C:\neura \Neura_Companion_OS_Legacy_WillHelper",
    "C:\neura \Neura_Companion_OS_Legacy_WillHelper_1"
)

Write-Host "=== Neura Companion Cleanup ===" -ForegroundColor Cyan
Write-Host ""

# Check what folders exist
$toDelete = @()
foreach ($folder in $redundantFolders) {
    if (Test-Path $folder) {
        $fileCount = (Get-ChildItem $folder -File -Recurse -ErrorAction SilentlyContinue).Count
        Write-Host "Found: $folder ($fileCount files)" -ForegroundColor Yellow
        $toDelete += $folder
    }
}

if ($toDelete.Count -eq 0) {
    Write-Host "No redundant folders found." -ForegroundColor Green
    exit
}

Write-Host ""
Write-Host "These folders are duplicates of files in neura_companion_merged:" -ForegroundColor Yellow
foreach ($f in $toDelete) {
    Write-Host "  - $f"
}

Write-Host ""
$confirm = Read-Host "Delete these folders? (yes/no)"

if ($confirm -eq "yes") {
    foreach ($folder in $toDelete) {
        Write-Host "Deleting $folder..." -ForegroundColor Red
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ""
    Write-Host "✓ Cleanup complete!" -ForegroundColor Green
} else {
    Write-Host "Cancelled." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Main project location: C:\neura\neura_companion_merged" -ForegroundColor Cyan
