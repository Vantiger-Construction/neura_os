#Requires -Version 5.1
<#
  Neura_Update_And_Prepare.ps1
  ---------------------------------------------------------------------------
  One deterministic pass to get the canonical Neura Flutter app dependency-
  clean, analyzed, tested, and built on a Windows development machine.

  Order (fail-fast, no guessing):
    GATE 0  Pin and validate the root. Echo pubspec name and Dart count.
    STEP 1  Run the gated Neura Dart repair tool.
    STEP 2  flutter clean
    STEP 3  flutter pub get
    GATE 1  flutter analyze -> MUST report 0 errors.
    STEP 4  flutter test, unless -SkipTests.
    STEP 5  flutter build windows --release, unless -NoBuild.
    OPT      flutter build apk --release when -BuildApk is supplied.
    DONE     Report the Windows Release directory used by packaging tools.

  This is repair/build automation only. It does not add features, merge sibling
  forks, remove load-bearing services, or create an installer.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\Neura_Update_And_Prepare.ps1 `
      -Root "C:\Users\user1\source\repos\Vantiger-Construction\Neura-O.S\neura\neura_comprehensive_merge\0"

  Options:
    -SkipRepair  Skip text normalization/targeted string repair.
    -SkipTests   Skip flutter test.
    -NoBuild     Stop after a clean analyzer/test gate.
    -BuildApk    Also produce an Android release APK.
    -Yes         Skip the GATE 0 confirmation prompt.
    -RepairTool  Explicit path to Neura-DartRepair.ps1.
  ---------------------------------------------------------------------------
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$RepairTool,
    [switch]$SkipRepair,
    [switch]$SkipTests,
    [switch]$NoBuild,
    [switch]$BuildApk,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    Write-Host $Message -ForegroundColor $Color
}

function Die([string]$Message, [int]$Code = 1) {
    Say ''
    Say "[X] $Message" Red
    exit $Code
}

function Resolve-ExistingFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return $null
    }
}

# ---- GATE 0: resolve and validate the exact root ---------------------------
try {
    $Root = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
} catch {
    Die "Root path does not exist: $Root"
}

$pubspecPath = Join-Path $Root 'pubspec.yaml'
$libPath = Join-Path $Root 'lib'
if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    Die "No pubspec.yaml at: $Root"
}
if (-not (Test-Path -LiteralPath $libPath -PathType Container)) {
    Die "No lib\ folder at: $Root"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Die 'flutter is not on PATH. Install Flutter or add its bin folder to PATH.'
}

$nameMatch = Select-String -LiteralPath $pubspecPath -Pattern '^\s*name:\s*(.+?)\s*$' |
    Select-Object -First 1
if (-not $nameMatch) {
    Die "Could not read the package name from: $pubspecPath"
}
$pkgName = $nameMatch.Matches[0].Groups[1].Value.Trim()
$dartCount = @(Get-ChildItem -LiteralPath $libPath -Recurse -File -Filter '*.dart' -ErrorAction SilentlyContinue).Count

Say ''
Say '==================== GATE 0: selected project ====================' Cyan
Say "  ROOT         = $Root"
Say "  pubspec name = $pkgName        (expected: neuro_companion)"
Say "  Dart files   = $dartCount"
if ($pkgName -ne 'neuro_companion') {
    Say "  [!] Package name is not 'neuro_companion'. Confirm this is the canonical" Yellow
    Say '      root and not one of the sibling or nested historical forks.' Yellow
}
Say ''
if (-not $Yes) {
    $answer = Read-Host 'Proceed against this tree? (y/N)'
    if ($answer -notmatch '^(?i:y|yes)$') {
        Die 'Aborted at GATE 0. Re-run with the correct -Root.' 0
    }
}

# ---- STEP 1: gated repair --------------------------------------------------
if (-not $SkipRepair) {
    if ($RepairTool) {
        $RepairTool = Resolve-ExistingFile $RepairTool
    } else {
        $candidates = @(
            (Join-Path $PSScriptRoot 'tools\neura_dart_repair\tools\Neura-DartRepair.ps1'),
            (Join-Path $PSScriptRoot 'tools\Neura-DartRepair.ps1'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Neura Dart Repair\tools\Neura-DartRepair.ps1'),
            (Join-Path $PSScriptRoot 'Neura_Dart_Repair_Windows_Installer_v1\tools\Neura-DartRepair.ps1'),
            (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\Neura-DartRepair.ps1')
        )
        $RepairTool = $candidates |
            ForEach-Object { Resolve-ExistingFile $_ } |
            Where-Object { $_ } |
            Select-Object -First 1
    }

    if (-not $RepairTool) {
        Die "Neura-DartRepair.ps1 not found. Pass -RepairTool '<path>' or use -SkipRepair."
    }

    Say ''
    Say '==================== STEP 1: gated repair ====================' Cyan
    Say "  tool = $RepairTool"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RepairTool `
        -Root $Root -RunAnalyzer -AutoFixStringLiterals
    $repairExit = $LASTEXITCODE
    if ($repairExit -ne 0) {
        Say "  [!] Repair tool exited $repairExit. GATE 1 remains the source of truth." Yellow
    }
}

Push-Location $Root
try {
    # ---- STEP 2: clean -----------------------------------------------------
    Say ''
    Say '==================== STEP 2: flutter clean ====================' Cyan
    & flutter clean
    if ($LASTEXITCODE -ne 0) { Die 'flutter clean failed.' }

    # ---- STEP 3: dependencies ---------------------------------------------
    Say ''
    Say '==================== STEP 3: flutter pub get ====================' Cyan
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Say ''
        Say '  A package failed to resolve. Do not overwrite pubspec.yaml from a' Yellow
        Say '  historical fork. Reconcile the failing dependency in this root.' Yellow
        Die 'flutter pub get failed.'
    }

    # ---- GATE 1: analyze must have zero errors -----------------------------
    Say ''
    Say '==================== GATE 1: flutter analyze ====================' Cyan
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $log = Join-Path $Root "analyze_$stamp.txt"

    # Warnings and infos are recorded but are not made fatal for this repair gate.
    & flutter analyze --no-fatal-warnings --no-fatal-infos *>&1 |
        Tee-Object -FilePath $log |
        Out-Host
    $analyzeExit = $LASTEXITCODE

    # Handles the normal Flutter format ("error -" / "error •") and Dart's
    # machine format ("ERROR|").
    $errorPattern = '^\s*(?:error\b|ERROR\|)'
    $errorCount = @(Select-String -LiteralPath $log -Pattern $errorPattern).Count

    Say ''
    Say "  Errors remaining : $errorCount"
    Say "  Analyzer exit    : $analyzeExit"
    Say "  Log              : $log"

    if ($errorCount -gt 0) {
        Say ''
        Say '  Normalization did not clear every error. Continue the measured,' Yellow
        Say '  leaves-inward repair described in docs\recovery\NEURA_CLAUDE_CODE_BRIEF.md,' Yellow
        Say '  then re-run this script. The app is not installer-ready yet.' Yellow
        Die "Stopped at GATE 1: $errorCount analyzer error(s) remain." 2
    }
    if ($analyzeExit -ne 0) {
        Die "flutter analyze exited $analyzeExit without a parsed error line. Review: $log" 2
    }

    # ---- STEP 4: tests -----------------------------------------------------
    if (-not $SkipTests) {
        Say ''
        Say '==================== STEP 4: flutter test ====================' Cyan
        & flutter test
        if ($LASTEXITCODE -ne 0) {
            Die 'flutter test failed. Fix the tests or explicitly re-run with -SkipTests.' 3
        }
    }

    if ($NoBuild) {
        Say ''
        Say 'Analyzer gate is clean. -NoBuild was supplied; stopping before release build.' Green
        exit 0
    }

    # ---- STEP 5: Windows release ------------------------------------------
    Say ''
    Say '==================== STEP 5: flutter build windows --release ====================' Cyan
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { Die 'Windows release build failed.' 4 }

    if ($BuildApk) {
        Say ''
        Say '==================== OPTIONAL: flutter build apk --release ====================' Cyan
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) { Die 'Android APK build failed.' 5 }
    }
} finally {
    Pop-Location
}

# ---- DONE: report packaging input -----------------------------------------
$releaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
Say ''
Say '==================== DONE ====================' Green
Say '  App analyzed, tested, and built from the selected canonical tree.'
if (Test-Path -LiteralPath $releaseDir) {
    Say "  Release dir : $releaseDir" Green
    Get-ChildItem -LiteralPath $releaseDir -Filter '*.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { Say ("    exe -> {0}" -f $_.Name) }
} else {
    Say "  [!] Expected Release directory was not found: $releaseDir" Yellow
}
Say ''
Say '  Next packaging choices:' Cyan
Say '    * MSIX kit  : tools\distribution_packaging_kit\windows\MSIX\'
Say '    * one-click : tools\oneclick_installer_kit\'
Say "    * beta ZIP  : package_beta.ps1 -RepoRoot `"$Root`" -AppVersion `"1.0.0-beta`""
Say ''
Say '  NOTE: tools\neura_dart_repair\installer\NeuraDartRepair.iss packages' Yellow
Say '        the repair utility, not the Neura application.' Yellow
exit 0
