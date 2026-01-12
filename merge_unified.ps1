# Merge all Neura Companion projects into unified structure
$desktop = [Environment]::GetFolderPath("Desktop")
$source = Join-Path $desktop "Neura Companion ver. 1.0.0.0"
$unified = Join-Path $source "_UNIFIED_BUILD"

Write-Host "Creating unified structure..." -ForegroundColor Cyan
New-Item -Path $unified -ItemType Directory -Force | Out-Null

# Create standard Flutter/Dart project structure
$dirs = @("lib", "assets", "android", "ios", "test", "docs", "scripts", "screenshots", "marketing", "firebase")
foreach ($dir in $dirs) {
    New-Item -Path (Join-Path $unified $dir) -ItemType Directory -Force | Out-Null
}

Write-Host "`nMerging source files..." -ForegroundColor Green

# Get all project folders
$projects = Get-ChildItem -Path $source -Directory | Where-Object { $_.Name -ne "_UNIFIED_BUILD" }

foreach ($project in $projects) {
    Write-Host "  Processing $($project.Name)..." -ForegroundColor Yellow
    
    # Merge lib files
    if (Test-Path (Join-Path $project.FullName "lib")) {
        Copy-Item -Path (Join-Path $project.FullName "lib\*") -Destination (Join-Path $unified "lib") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge assets
    if (Test-Path (Join-Path $project.FullName "assets")) {
        Copy-Item -Path (Join-Path $project.FullName "assets\*") -Destination (Join-Path $unified "assets") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge android
    if (Test-Path (Join-Path $project.FullName "android")) {
        Copy-Item -Path (Join-Path $project.FullName "android\*") -Destination (Join-Path $unified "android") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge iOS
    if (Test-Path (Join-Path $project.FullName "ios")) {
        Copy-Item -Path (Join-Path $project.FullName "ios\*") -Destination (Join-Path $unified "ios") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge docs
    if (Test-Path (Join-Path $project.FullName "docs")) {
        Copy-Item -Path (Join-Path $project.FullName "docs\*") -Destination (Join-Path $unified "docs") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge scripts
    if (Test-Path (Join-Path $project.FullName "scripts")) {
        Copy-Item -Path (Join-Path $project.FullName "scripts\*") -Destination (Join-Path $unified "scripts") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge screenshots
    if (Test-Path (Join-Path $project.FullName "screenshots")) {
        Copy-Item -Path (Join-Path $project.FullName "screenshots\*") -Destination (Join-Path $unified "screenshots") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge marketing
    if (Test-Path (Join-Path $project.FullName "marketing")) {
        Copy-Item -Path (Join-Path $project.FullName "marketing\*") -Destination (Join-Path $unified "marketing") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Merge firebase
    if (Test-Path (Join-Path $project.FullName "firebase")) {
        Copy-Item -Path (Join-Path $project.FullName "firebase\*") -Destination (Join-Path $unified "firebase") -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Copy pubspec.yaml if it exists (will be overwritten by later versions)
    if (Test-Path (Join-Path $project.FullName "pubspec.yaml")) {
        Copy-Item -Path (Join-Path $project.FullName "pubspec.yaml") -Destination (Join-Path $unified "pubspec.yaml") -Force -ErrorAction SilentlyContinue
    }
    
    # Copy README files
    if (Test-Path (Join-Path $project.FullName "README.md")) {
        $readmeDest = Join-Path $unified "docs\README_$($project.Name).md"
        Copy-Item -Path (Join-Path $project.FullName "README.md") -Destination $readmeDest -Force -ErrorAction SilentlyContinue
    }
}

# Create main README
$mainReadme = @"
# Neura Companion OS v1.0.0.0

Unified build consolidating all Neura Companion modules and features.

## Merged Projects
$($projects.Name -join "`n- ")

## Structure
- **lib/** - All Dart source code
- **assets/** - Images, fonts, audio files
- **android/** - Android native code
- **ios/** - iOS native code
- **firebase/** - Firebase configuration
- **docs/** - Documentation from all projects
- **scripts/** - Build and deployment scripts
- **screenshots/** - App screenshots
- **marketing/** - Marketing materials

## Build Date
$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Next Steps
1. Review and merge pubspec.yaml dependencies
2. Resolve any duplicate class names in lib/
3. Test build with: flutter pub get && flutter run
"@

Set-Content -Path (Join-Path $unified "README.md") -Value $mainReadme

Write-Host "`n✓ Unified build created!" -ForegroundColor Green
Write-Host "Location: $unified" -ForegroundColor Cyan
Write-Host "`nNext: Review lib/ for duplicates and merge pubspec.yaml files" -ForegroundColor Yellow

explorer $unified
