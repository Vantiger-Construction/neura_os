#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$scriptPath = Join-Path $PSScriptRoot 'Repair-NeuraCiStorage.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Recovery script syntax errors: $errors" }
foreach ($definition in $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

function New-FixtureFile {
    param([string]$Path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, 'fixture')
}
function Assert-FixtureExists {
    param([string]$Path, [bool]$Expected = $true)
    if ((Test-Path -LiteralPath $Path) -ne $Expected) { throw "Unexpected existence: $Path" }
}
$script:javaActive = $false
function Get-Process {
    param([string[]]$Name, $ErrorAction)
    if ($script:javaActive) { return [pscustomobject]@{ Id = 42 } }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('neura-storage-' + [guid]::NewGuid().ToString('N'))
$toolCache = Join-Path $fixture 'tools'
$flutter = Join-Path $toolCache 'flutter'
$stage = Join-Path $flutter '3.47.5/.install'
$gradle = Join-Path $toolCache 'neura-android/gradle-home'
$derived = Join-Path $gradle 'caches/8.13/transforms'
$protected = @(
    (Join-Path $flutter '3.44.7/x64/bin/flutter.bat'),
    (Join-Path $flutter '3.47.5/x64.previous/bin/flutter.bat'),
    (Join-Path $gradle 'caches/modules-2/dependency.jar'),
    (Join-Path $gradle 'wrapper/dists/gradle.zip'),
    (Join-Path $toolCache 'neura-android/sdk-36.0.0-ndk-28.2.13676358/tool.exe'),
    (Join-Path $toolCache 'neura-android/jdk-17.0.19+10/bin/java.exe'),
    (Join-Path $fixture 'neura-packages/android/recovery.apk'),
    (Join-Path $fixture 'source/keep.dart'),
    (Join-Path $flutter 'unrelated/.install/keep.txt')
)
$lock = $null
$links = @()
$originalRunId = $env:GITHUB_RUN_ID
$originalRunAttempt = $env:GITHUB_RUN_ATTEMPT
try {
    $env:GITHUB_RUN_ID = '999'
    $env:GITHUB_RUN_ATTEMPT = '1'
    foreach ($path in $protected) { New-FixtureFile -Path $path }
    $readOnlyFile = Join-Path $stage 'extract/flutter/file.bin'
    New-FixtureFile -Path $readOnlyFile
    [IO.File]::SetAttributes($readOnlyFile, [IO.FileAttributes]::ReadOnly)
    New-FixtureFile -Path (Join-Path $derived 'generated.bin')
    $buildCache = Join-Path $gradle 'caches/build-cache-1'
    New-FixtureFile -Path (Join-Path $buildCache 'generated.bin')
    $jarCache = Join-Path $gradle 'caches/jars-9'
    New-FixtureFile -Path (Join-Path $jarCache 'generated.jar')
    $daemonCache = Join-Path $gradle 'daemon/8.14'
    New-FixtureFile -Path (Join-Path $daemonCache 'daemon.log')
    $packageRoot = Join-Path $fixture 'neura-packages/android'
    foreach ($number in 100..104) {
        $package = Join-Path $packageRoot "$number-1/package.apk"
        New-FixtureFile -Path $package
        (Get-Item -LiteralPath (Split-Path -Parent $package)).LastWriteTime =
            (Get-Date).AddDays($number - 105)
    }
    $activePackage = Join-Path $packageRoot '999-1/package.apk'
    New-FixtureFile -Path $activePackage
    (Get-Item -LiteralPath (Split-Path -Parent $activePackage)).LastWriteTime =
        (Get-Date).AddDays(-10)
    Invoke-NeuraStorageRecovery -ToolCache $toolCache
    Remove-NeuraStalePackageRuns -Root (Join-Path $fixture 'neura-packages')
    foreach ($path in $protected) { Assert-FixtureExists -Path $path }
    foreach ($path in @($stage, $derived, $buildCache, $jarCache, $daemonCache)) {
        Assert-FixtureExists -Path $path -Expected $false
    }
    foreach ($number in 100..101) {
        Assert-FixtureExists -Path (Join-Path $packageRoot "$number-1") -Expected $false
    }
    foreach ($number in 102..104) {
        Assert-FixtureExists -Path (Join-Path $packageRoot "$number-1")
    }
    Assert-FixtureExists -Path (Join-Path $packageRoot '999-1')
    Write-Host 'PASS: derived caches and stale delivered packages removed; tools, dependency downloads, three recent packages, backups, and source preserved.'

    New-FixtureFile -Path (Join-Path $stage 'active.bin')
    $lockPath = Join-Path $flutter '.3.47.5.install.lock'
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    Invoke-NeuraStorageRecovery -ToolCache $toolCache
    Assert-FixtureExists -Path (Join-Path $stage 'active.bin')
    $lock.Dispose()
    $lock = $null
    Write-Host 'PASS: an active Flutter install is protected by its real lock.'

    New-FixtureFile -Path (Join-Path $derived 'busy.bin')
    $script:javaActive = $true
    Invoke-NeuraStorageRecovery -ToolCache $toolCache
    Assert-FixtureExists -Path (Join-Path $derived 'busy.bin')
    $script:javaActive = $false
    Write-Host 'PASS: Gradle derived output is retained while Java is active.'

    $outside = Join-Path $fixture 'outside'
    New-FixtureFile -Path (Join-Path $outside 'keep.txt')
    $linked = Join-Path $derived 'external-link'
    $kind = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $kind -Path $linked -Target $outside | Out-Null
    $links += $linked
    Invoke-NeuraStorageRecovery -ToolCache $toolCache
    Assert-FixtureExists -Path (Join-Path $outside 'keep.txt')
    Assert-FixtureExists -Path $linked
    Write-Host 'PASS: a nested link cannot delete external files.'

    $linkedRoot = Join-Path $fixture 'linked-tools'
    New-Item -ItemType $kind -Path $linkedRoot -Target $toolCache | Out-Null
    $links += $linkedRoot
    New-FixtureFile -Path (Join-Path $stage 'linked-root-keep.bin')
    Invoke-NeuraStorageRecovery -ToolCache $linkedRoot
    Assert-FixtureExists -Path (Join-Path $stage 'linked-root-keep.bin')
    Write-Host 'PASS: a linked tool-cache root is left untouched.'

    $reportStage = Join-Path $flutter '9.9.9/.install'
    New-FixtureFile -Path (Join-Path $reportStage 'keep.bin')
    Invoke-NeuraStorageRecovery -ToolCache $toolCache -ReportOnly
    Assert-FixtureExists -Path (Join-Path $reportStage 'keep.bin')
    Assert-FixtureExists -Path (Join-Path $flutter '.9.9.9.install.lock') -Expected $false
    Write-Host 'PASS: report-only mode neither deletes data nor creates an install lock.'
} finally {
    $env:GITHUB_RUN_ID = $originalRunId
    $env:GITHUB_RUN_ATTEMPT = $originalRunAttempt
    if ($lock) { $lock.Dispose() }
    foreach ($link in $links) {
        if ($env:OS -eq 'Windows_NT') { & "$env:SystemRoot\System32\cmd.exe" /d /c rmdir "$link" }
        else { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
