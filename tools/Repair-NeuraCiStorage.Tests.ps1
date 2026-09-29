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
$script:workerCount = 1
function Get-Process {
    param([string[]]$Name, $ErrorAction)
    if ('Runner.Worker' -in $Name) {
        for ($i = 0; $i -lt $script:workerCount; $i++) { [pscustomobject]@{ Id = $i + 1 } }
    } elseif ($script:javaActive) { return [pscustomobject]@{ Id = 42 } }
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
    $recentPackage = Join-Path $packageRoot '105-1/package.apk'
    New-FixtureFile -Path $recentPackage
    (Get-Item -LiteralPath (Split-Path -Parent $recentPackage)).LastWriteTime =
        (Get-Date).AddMinutes(-30)
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
    foreach ($number in 100..104) {
        Assert-FixtureExists -Path (Join-Path $packageRoot "$number-1") -Expected $false
    }
    Assert-FixtureExists -Path (Join-Path $packageRoot '105-1')
    Assert-FixtureExists -Path (Join-Path $packageRoot '999-1')
    Write-Host 'PASS: derived caches and aged delivered packages removed; tools, dependency downloads, recent/current packages, backups, and source preserved.'

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

    $runner = Join-Path $fixture 'runner'
    $runnerTemp = Join-Path $runner '_work/_temp'
    $checkout = Join-Path $runner '_work/neura_os/neura_os'
    $agedPaths = @(
        (Join-Path $checkout '.dart_tool'),
        (Join-Path $checkout 'source/android/.gradle'),
        (Join-Path $checkout 'source/rust/target')
    )
    foreach ($path in $agedPaths) {
        New-FixtureFile -Path (Join-Path $path 'generated.bin')
        (Get-Item -LiteralPath $path -Force).LastWriteTime = (Get-Date).AddDays(-1)
    }
    $retainedPaths = @(
        (Join-Path $checkout 'lib/keep.dart'),
        (Join-Path $checkout 'source/pubspec.lock'),
        (Join-Path $checkout 'source/build/recent.bin'),
        (Join-Path $runner '_work/another_repo/another_repo/.dart_tool/keep.bin'),
        (Join-Path $runner '_work/_actions/actions/checkout/v5/keep.js'),
        (Join-Path $runner '_diag/Worker_recent.log'),
        (Join-Path $runner '_diag/unrelated.log'),
        (Join-Path $runnerTemp 'recent.bin')
    )
    foreach ($path in $retainedPaths) { New-FixtureFile -Path $path }
    $oldDiagnostic = Join-Path $runner '_diag/Worker_old.log'
    New-FixtureFile -Path $oldDiagnostic
    (Get-Item -LiteralPath $oldDiagnostic).LastWriteTime = (Get-Date).AddDays(-8)
    foreach ($number in 1..27) {
        $tempDirectory = Join-Path $runnerTemp "old-$number"
        New-FixtureFile -Path (Join-Path $tempDirectory 'generated.bin')
        (Get-Item -LiteralPath $tempDirectory).LastWriteTime = (Get-Date).AddDays(-1)
    }
    Invoke-NeuraRunnerRecovery -RunnerTemp $runnerTemp -ReportOnly
    foreach ($path in $agedPaths) { Assert-FixtureExists -Path $path }
    Assert-FixtureExists -Path $oldDiagnostic
    if (@(Get-ChildItem -LiteralPath $runnerTemp -Directory).Count -ne 27) { throw 'Report-only removed temp data.' }
    $script:workerCount = 2
    Invoke-NeuraRunnerRecovery -RunnerTemp $runnerTemp
    foreach ($path in $agedPaths) { Assert-FixtureExists -Path $path }
    $script:workerCount = 1
    $script:javaActive = $true
    Invoke-NeuraRunnerRecovery -RunnerTemp $runnerTemp
    foreach ($path in $agedPaths) { Assert-FixtureExists -Path $path }
    $script:javaActive = $false
    Invoke-NeuraRunnerRecovery -RunnerTemp $runnerTemp
    foreach ($path in $agedPaths) { Assert-FixtureExists -Path $path -Expected $false }
    Assert-FixtureExists -Path $oldDiagnostic -Expected $false
    foreach ($path in $retainedPaths) { Assert-FixtureExists -Path $path }
    if (@(Get-ChildItem -LiteralPath $runnerTemp -Directory).Count -ne 3) { throw 'Temp cleanup exceeded its 24-entry bound.' }
    Write-Host 'PASS: bounded aged checkout/temp/log cleanup preserves source, actions, recent data, and active work.'

    # A linked ancestor of an apparently ordinary generated folder is unsafe.
    $outsideGenerated = Join-Path $outside '.dart_tool'
    New-FixtureFile -Path (Join-Path $outsideGenerated 'keep.bin')
    (Get-Item -LiteralPath $outsideGenerated -Force).LastWriteTime = (Get-Date).AddDays(-1)
    $sourcePath = Join-Path $checkout 'source'
    Remove-Item -LiteralPath $sourcePath -Recurse -Force
    New-Item -ItemType $kind -Path $sourcePath -Target $outside | Out-Null
    $links += $sourcePath
    Invoke-NeuraRunnerRecovery -RunnerTemp $runnerTemp
    Assert-FixtureExists -Path (Join-Path $outsideGenerated 'keep.bin')
    $unexpectedTemp = Join-Path $fixture 'personal/_temp'
    New-FixtureFile -Path (Join-Path $unexpectedTemp 'keep.bin')
    (Get-Item -LiteralPath (Join-Path $unexpectedTemp 'keep.bin')).LastWriteTime = (Get-Date).AddDays(-1)
    Invoke-NeuraRunnerRecovery -RunnerTemp $unexpectedTemp
    Assert-FixtureExists -Path (Join-Path $unexpectedTemp 'keep.bin')
    Write-Host 'PASS: linked ancestors and unexpected runner layouts cannot reach external files.'

    $validationRoot = Join-Path $fixture 'neura-ci/999-1/state-matrix'
    $validationGenerated = @(
        'workspace/build/test_cache/compiled.bin',
        'workspace/.dart_tool/package_config.json',
        'workspace/android/.gradle/generated.bin',
        'workspace/rust/target/generated.bin',
        'workspace/.packages',
        'temp/flutter-test/output.bin'
    )
    $validationRetained = @(
        'workspace/.git/config', 'workspace/lib/keep.dart',
        'workspace/pubspec.lock', 'workspace/state-matrix.log',
        'pub-cache/keep.bin'
    )
    foreach ($relative in ($validationGenerated + $validationRetained)) {
        New-FixtureFile -Path (Join-Path $validationRoot $relative)
    }
    Clear-NeuraValidationOutput -RunRoot $validationRoot -RunKey '999-1' -ReportOnly
    Clear-NeuraValidationOutput -RunRoot $validationRoot -RunKey '1000-1'
    Clear-NeuraValidationOutput -RunRoot $null -RunKey '999-1'
    foreach ($relative in $validationGenerated) {
        Assert-FixtureExists -Path (Join-Path $validationRoot $relative)
    }
    # Exercise the real script entry point too; it must not run global recovery.
    & $scriptPath -ClearValidationOutput -ValidationRunRoot $validationRoot -ToolCache $toolCache
    foreach ($relative in $validationGenerated) {
        Assert-FixtureExists -Path (Join-Path $validationRoot $relative) -Expected $false
    }
    foreach ($relative in $validationRetained) {
        Assert-FixtureExists -Path (Join-Path $validationRoot $relative)
    }
    Assert-FixtureExists -Path (Join-Path $reportStage 'keep.bin')
    Write-Host 'PASS: finishing-job cleanup releases only its generated data; source, logs, shared caches, other jobs, and report-only data remain protected.'

    $foreignRoot = Join-Path $fixture 'personal/999-1/state-matrix'
    New-FixtureFile -Path (Join-Path $foreignRoot 'temp/keep.bin')
    Clear-NeuraValidationOutput -RunRoot $foreignRoot -RunKey '999-1'
    Assert-FixtureExists -Path (Join-Path $foreignRoot 'temp/keep.bin')
    $linkedValidationRoot = Join-Path $fixture 'neura-ci/999-1/living-intelligence'
    New-Item -ItemType $kind -Path $linkedValidationRoot -Target $foreignRoot | Out-Null
    $links += $linkedValidationRoot
    Clear-NeuraValidationOutput -RunRoot $linkedValidationRoot -RunKey '999-1'
    Assert-FixtureExists -Path (Join-Path $foreignRoot 'temp/keep.bin')
    $linkedOutput = Join-Path $validationRoot 'workspace/build'
    New-Item -ItemType $kind -Path $linkedOutput -Target $outside | Out-Null
    $links += $linkedOutput
    Clear-NeuraValidationOutput -RunRoot $validationRoot -RunKey '999-1'
    Assert-FixtureExists -Path (Join-Path $outside 'keep.txt')
    Write-Host 'PASS: finishing-job cleanup rejects foreign roots and preserves linked output and external targets.'
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
