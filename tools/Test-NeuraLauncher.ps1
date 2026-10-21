#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-LauncherFixture {
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$ToolLog,
        [Parameter(Mandatory)][int]$ExpectedExit
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(
            & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -NoLaunch 2>&1
        )
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne $ExpectedExit) {
        throw (
            "Launcher fixture exited with $exitCode; expected $ExpectedExit." +
            [Environment]::NewLine +
            ($output -join [Environment]::NewLine)
        )
    }
    if (Test-Path -LiteralPath $ToolLog -PathType Leaf) {
        return (Get-Content -LiteralPath $ToolLog -Raw)
    }
    return ''
}

foreach ($scriptName in @(
    'Start-Neura.ps1',
    'Install-NeuraShortcut.ps1',
    'Build-Neura-LocalBrain.ps1'
)) {
    $tokens = $null
    $errors = $null
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    [void][Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$errors
    )
    Assert-True ($errors.Count -eq 0) "$scriptName has PowerShell syntax errors."
}

$launcherText = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'Start-Neura.ps1'
) -Raw
foreach ($contract in @(
    'git -C $root diff --no-ext-diff --binary HEAD --',
    'ls-files --others --exclude-standard',
    'Get-FilesystemSourceStamp',
    'Get-IncompleteNeuraPayload',
    'flutter pub get --enforce-lockfile',
    'NeuraCompanionLauncher-',
    'http://127.0.0.1:11434/api/version',
    '$handler.UseProxy = $false'
)) {
    Assert-True (
        $launcherText.Contains($contract)
    ) "Launcher contract is missing: $contract"
}

$batchRoot = Join-Path ([IO.Path]::GetTempPath()) "neura batch fixture $PID"
$sourceRoot = Join-Path ([IO.Path]::GetTempPath()) "neura source fixture $PID"
$oldPath = $env:PATH
$oldToolLog = $env:NEURA_TEST_TOOL_LOG
$toolLog = $null
try {
    New-Item -ItemType Directory -Path (Join-Path $batchRoot 'tools') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\Neura.bat') -Destination $batchRoot
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\RUN_NEURA_LOCAL_BRAIN.bat') -Destination $batchRoot
    Set-Content -LiteralPath (
        Join-Path $batchRoot 'tools\Install-NeuraShortcut.ps1'
    ) -Value 'exit 0' -Encoding ASCII
    Set-Content -LiteralPath (
        Join-Path $batchRoot 'tools\Start-Neura.ps1'
    ) -Value 'exit 23' -Encoding ASCII

    Push-Location $batchRoot
    try {
        $batchOutput = @(
            & $env:ComSpec /d /c 'echo.| call RUN_NEURA_LOCAL_BRAIN.bat -NoLaunch' 2>&1
        )
        $batchExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    Assert-True ($batchExit -eq 23) (
        'Launcher batch wrappers did not preserve exit code 23.' +
        [Environment]::NewLine +
        ($batchOutput -join [Environment]::NewLine)
    )

    $fixtureTools = Join-Path $sourceRoot 'tools'
    $fakeBin = Join-Path $sourceRoot 'fake-bin'
    $release = Join-Path $sourceRoot 'build\windows\x64\runner\Release'
    $assets = Join-Path $release 'data\flutter_assets'
    foreach ($directory in @(
        $fixtureTools,
        $fakeBin,
        (Join-Path $sourceRoot 'lib'),
        $assets
    )) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-Neura.ps1') -Destination $fixtureTools
    Set-Content -LiteralPath (Join-Path $sourceRoot 'pubspec.yaml') -Value 'name: neura_fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $sourceRoot 'pubspec.lock') -Value 'packages: {}' -Encoding ASCII
    $sourceFile = Join-Path $sourceRoot 'lib\main.dart'
    Set-Content -LiteralPath $sourceFile -Value 'void main() {}' -Encoding ASCII

    foreach ($relativePath in @(
        'neuro_companion.exe',
        'neura_api.exe',
        'neura_swarm.dll',
        'flutter_windows.dll',
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'data\icudtl.dat',
        'data\app.so',
        'data\flutter_assets\AssetManifest.bin'
    )) {
        $path = Join-Path $release $relativePath
        $parent = Split-Path -Parent $path
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Set-Content -LiteralPath $path -Value 'fixture' -Encoding ASCII
    }

    $toolLog = Join-Path ([IO.Path]::GetTempPath()) "neura launcher tool log $PID.txt"
    Set-Content -LiteralPath (Join-Path $fakeBin 'git.cmd') -Encoding ASCII -Value @(
        '@echo off',
        'exit /b 1'
    )
    Set-Content -LiteralPath (Join-Path $fakeBin 'cargo.cmd') -Encoding ASCII -Value @(
        '@echo off',
        'exit /b 0'
    )
    Set-Content -LiteralPath (Join-Path $fakeBin 'flutter.cmd') -Encoding ASCII -Value @(
        '@echo off',
        'echo %*>>"%NEURA_TEST_TOOL_LOG%"',
        'exit /b 0'
    )

    $env:PATH = "$fakeBin;$oldPath"
    $env:NEURA_TEST_TOOL_LOG = $toolLog
    $fixtureLauncher = Join-Path $fixtureTools 'Start-Neura.ps1'

    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $firstLog = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($firstLog -match 'pub get --enforce-lockfile') 'Initial source-export build skipped locked dependency verification.'
    Assert-True ($firstLog -match 'build windows --release') 'Initial source-export build did not invoke the Windows build.'

    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $secondLog = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($secondLog)) 'Unchanged source-export inputs rebuilt unexpectedly.'

    Set-Content -LiteralPath $sourceFile -Value 'void main() { print("changed"); }' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $changedLog = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($changedLog -match 'build windows --release') 'Changed source-export input did not force a rebuild.'

    Set-Content -LiteralPath (Join-Path $release 'neura_api.exe') -Value '' -Encoding ASCII -NoNewline
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    [void](Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 1)

    Remove-Item -LiteralPath (Join-Path $release 'neura_api.exe') -Force
    New-Item -ItemType Directory -Path (Join-Path $release 'neura_api.exe') | Out-Null
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    [void](Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 1)
} finally {
    $env:PATH = $oldPath
    $env:NEURA_TEST_TOOL_LOG = $oldToolLog
    Remove-Item -LiteralPath $batchRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sourceRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ($toolLog) {
        Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Neura launcher syntax, freshness, payload, path, and exit-code contracts passed.'
