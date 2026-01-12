# Fast Consolidation - Copy existing folders only
$desktop = [Environment]::GetFolderPath("Desktop")
$destination = Join-Path $desktop "Neura Companion ver. 1.0.0.0"

Write-Host "Creating destination folder..." -ForegroundColor Cyan
New-Item -Path $destination -ItemType Directory -Force | Out-Null

# Source folders to consolidate (already extracted)
$sourceFolders = @(
    "C:\neura\Neura_Companion_OS_FullMerged_vLatest",
    "C:\neura\Neura_Companion_ReadyToRun_FullBuild",
    "C:\neura\NeuraCompanion_FullSource_FinishedCore",
    "C:\neura\Neura_Final_MegaBuild",
    "C:\neura\Neura_Companion_FullBuild_STT_SmartHome_Billing_Diagnostics",
    "C:\neura\neura_companion_full_project_bundle_20251127_055131",
    "C:\neura\Neura_Complete_AI_Module",
    "C:\neura\Neura_Master_AllPhases"
)

Write-Host "`nCopying main source folders..." -ForegroundColor Green
foreach ($folder in $sourceFolders) {
    if (Test-Path $folder) {
        $folderName = Split-Path $folder -Leaf
        Write-Host "  Copying $folderName..." -ForegroundColor Yellow
        Copy-Item -Path $folder -Destination (Join-Path $destination $folderName) -Recurse -Force
    }
}

Write-Host "`n✓ Consolidation complete!" -ForegroundColor Green
Write-Host "Location: $destination" -ForegroundColor Cyan
explorer $destination
