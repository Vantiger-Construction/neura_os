#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-TestTextSha256([string]$Text) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return (-join ($algorithm.ComputeHash($bytes) |
            ForEach-Object { $_.ToString('x2') }))
    } finally {
        $algorithm.Dispose()
    }
}

function Invoke-QuietNative {
    param([Parameter(Mandatory)][scriptblock]$Command)

    # Windows PowerShell 5.1 turns redirected native stderr (git hints and
    # warnings) into a terminating error under ErrorActionPreference Stop.
    $ErrorActionPreference = 'Continue'
    & $Command 2>&1
}

function Invoke-LauncherFixture {
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$ToolLog,
        [Parameter(Mandatory)][int]$ExpectedExit,
        [switch]$Rebuild
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $arguments = @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $Script,
            '-NoLaunch'
        )
        if ($Rebuild) {
            $arguments += '-Rebuild'
        }
        $output = @(& powershell.exe @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
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
    $log = if (Test-Path -LiteralPath $ToolLog -PathType Leaf) {
        Get-Content -LiteralPath $ToolLog -Raw
    } else {
        ''
    }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
        ToolLog = $log
    }
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
    'ls-tree -r',
    '-- $sourcePaths',
    'ls-files --others',
    'Get-FilesystemSourceStamp',
    'Get-IncompleteNeuraPayload',
    'Write-NeuraPayloadManifest',
    'Sync-NeuraLocalSupportFiles',
    'Ensure-NeuraRuntimeLibraries',
    'tools/Start-NeuraLocalConversation.ps1',
    'windows/cmake',
    'flutter pub get --enforce-lockfile',
    'NeuraCompanionLauncher-',
    'http://127.0.0.1:11434/api/version',
    '$handler.UseProxy = $false',
    'Neura exited immediately without opening'
)) {
    Assert-True (
        $launcherText.Contains($contract)
    ) "Launcher contract is missing: $contract"
}

$builderText = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'Build-Neura-LocalBrain.ps1'
) -Raw
Assert-True (
    $builderText.Contains("Start-Neura.ps1') -Rebuild")
) 'Local-brain build does not force the canonical package refresh before launch.'

$shortcutText = Get-Content -LiteralPath (
    Join-Path $PSScriptRoot 'Install-NeuraShortcut.ps1'
) -Raw
foreach ($shortcutContract in @(
    'neura_shortcut.lock',
    '$existing.Arguments',
    '$link.Arguments = ',
    '$existing.Description',
    '$existing.WindowStyle'
)) {
    Assert-True ($shortcutText.Contains($shortcutContract)) `
        "Shortcut contract is missing: $shortcutContract"
}

$fixtureId = [Guid]::NewGuid().ToString('N')
$batchRoot = Join-Path ([IO.Path]::GetTempPath()) "neura batch fixture $fixtureId"
$sourceRoot = Join-Path ([IO.Path]::GetTempPath()) "neura source fixture $fixtureId"
$oldPath = $env:PATH
$oldToolLog = $env:NEURA_TEST_TOOL_LOG
$oldFailBuild = $env:NEURA_TEST_FAIL_BUILD
$oldSkipApi = $env:NEURA_TEST_SKIP_API
$oldSkipPlugin = $env:NEURA_TEST_SKIP_PLUGIN
$oldProgramFiles = $env:ProgramFiles
$oldProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$toolLog = $null
$fixtureMutex = $null
$fixtureMutexHeld = $false
$fixtureBuildLock = $null
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
            Invoke-QuietNative {
                & $env:ComSpec /d /c 'echo.| call RUN_NEURA_LOCAL_BRAIN.bat -NoLaunch'
            }
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
    $fakeProgramFiles = Join-Path $sourceRoot 'fake-program-files'
    $fakeRedist = Join-Path $fakeProgramFiles (
        # Versioned above any real toolset so a Visual Studio install on the
        # host can never outrank the fixture runtime set.
        'Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\99.99.99999' +
        '\x64\Microsoft.VC143.CRT'
    )
    $release = Join-Path $sourceRoot 'build\windows\x64\runner\Release'
    $assets = Join-Path $release 'data\flutter_assets'
    $offlineText = Join-Path $release 'offline-text'
    foreach ($directory in @(
        $fixtureTools,
        $fakeBin,
        $fakeRedist,
        (Join-Path $sourceRoot 'lib'),
        $assets,
        $offlineText
    )) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-Neura.ps1') -Destination $fixtureTools
    Set-Content -LiteralPath (Join-Path $sourceRoot 'pubspec.yaml') -Value 'name: neura_fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $sourceRoot 'pubspec.lock') -Value 'packages: {}' -Encoding ASCII
    $sourceFile = Join-Path $sourceRoot 'lib\main.dart'
    Set-Content -LiteralPath $sourceFile -Value 'void main() {}' -Encoding ASCII

    foreach ($supportName in @(
        'Start-NeuraLocalConversation.ps1',
        'NeuraLocalConversationPolicy.ps1',
        'NeuraLocalConversationProcess.cs'
    )) {
        Set-Content -LiteralPath (Join-Path $fixtureTools $supportName) `
            -Value "fixture $supportName" -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $offlineText $supportName) `
            -Value "fixture $supportName" -Encoding ASCII
    }

    foreach ($relativePath in @(
        'neuro_companion.exe',
        'neura_api.exe',
        'neura_swarm.dll',
        'flutter_windows.dll',
        'sample_plugin.dll',
        'data\icudtl.dat',
        'data\app.so',
        'data\flutter_assets\AssetManifest.bin'
    )) {
        $path = Join-Path $release $relativePath
        $parent = Split-Path -Parent $path
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Set-Content -LiteralPath $path -Value 'fixture' -Encoding ASCII
    }

    foreach ($runtimeName in @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )) {
        Set-Content -LiteralPath (Join-Path $fakeRedist $runtimeName) `
            -Value "fixture $runtimeName" -Encoding ASCII
    }

    $toolLog = Join-Path ([IO.Path]::GetTempPath()) "neura launcher tool log $fixtureId.txt"
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
        'if /i "%1 %2 %3"=="build windows --release" if "%NEURA_TEST_FAIL_BUILD%"=="1" exit /b 42',
        'if /i "%1 %2 %3"=="build windows --release" (',
        '  set "RELEASE=%~dp0..\build\windows\x64\runner\Release"',
        '  mkdir "%~dp0..\build\windows\x64\runner\Release\data\flutter_assets"',
        '  for %%F in (neuro_companion.exe neura_swarm.dll flutter_windows.dll) do >"%~dp0..\build\windows\x64\runner\Release\%%F" echo fixture',
        '  if not "%NEURA_TEST_SKIP_API%"=="1" >"%~dp0..\build\windows\x64\runner\Release\neura_api.exe" echo fixture',
        '  if not "%NEURA_TEST_SKIP_PLUGIN%"=="1" >"%~dp0..\build\windows\x64\runner\Release\sample_plugin.dll" echo fixture',
        '  >"%~dp0..\build\windows\x64\runner\Release\data\icudtl.dat" echo fixture',
        '  >"%~dp0..\build\windows\x64\runner\Release\data\app.so" echo fixture',
        '  >"%~dp0..\build\windows\x64\runner\Release\data\flutter_assets\AssetManifest.bin" echo fixture',
        ')',
        'exit /b 0'
    )

    $env:PATH = "$fakeBin;$oldPath"
    $env:NEURA_TEST_TOOL_LOG = $toolLog
    $env:NEURA_TEST_FAIL_BUILD = $null
    $env:NEURA_TEST_SKIP_API = $null
    $env:NEURA_TEST_SKIP_PLUGIN = $null
    $env:ProgramFiles = $fakeProgramFiles
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $fakeProgramFiles)
    $fixtureLauncher = Join-Path $fixtureTools 'Start-Neura.ps1'

    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $first = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($first.ToolLog -match 'pub get --enforce-lockfile') 'Initial source-export build skipped locked dependency verification.'
    Assert-True ($first.ToolLog -match 'build windows --release') 'Initial source-export build did not invoke the Windows build.'
    foreach ($runtimeName in @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )) {
        $runtimePath = Join-Path $release $runtimeName
        Assert-True (
            (Test-Path -LiteralPath $runtimePath -PathType Leaf) -and
            (Get-Item -LiteralPath $runtimePath).Length -gt 0
        ) "The first build did not package $runtimeName from the verified redist."
    }

    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $second = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($second.ToolLog)) 'Unchanged source-export inputs rebuilt unexpectedly.'

    $rollbackPaths = @(
        (Join-Path $release 'neuro_companion.exe'),
        (Join-Path $sourceRoot 'build\neura_launcher.payload.json'),
        (Join-Path $sourceRoot 'build\neura_launcher.stamp')
    )
    $rollbackBytes = @{}
    foreach ($rollbackPath in $rollbackPaths) {
        $rollbackBytes[$rollbackPath] = [Convert]::ToBase64String(
            [IO.File]::ReadAllBytes($rollbackPath)
        )
    }
    $env:NEURA_TEST_FAIL_BUILD = '1'
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $failedBuild = Invoke-LauncherFixture -Script $fixtureLauncher `
        -ToolLog $toolLog -ExpectedExit 1 -Rebuild
    $env:NEURA_TEST_FAIL_BUILD = $null
    Assert-True ($failedBuild.ToolLog -match 'build windows --release') `
        'The rollback fixture did not invoke the Windows build.'
    Assert-True ($failedBuild.Output -match 'flutter build windows failed') `
        'A failed Windows build did not report its original error.'
    foreach ($rollbackPath in $rollbackPaths) {
        Assert-True (Test-Path -LiteralPath $rollbackPath -PathType Leaf) `
            "Rollback did not restore $rollbackPath."
        $restoredBytes = [Convert]::ToBase64String(
            [IO.File]::ReadAllBytes($rollbackPath)
        )
        Assert-True ($restoredBytes -ceq $rollbackBytes[$rollbackPath]) `
            "Rollback changed the prior verified file: $rollbackPath"
    }
    $rollbackResidue = @(
        Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'build') `
            -Recurse -Force |
            Where-Object {
                $_.Name -match '\.neura-(backup|candidate|failed)-'
            }
    )
    Assert-True ($rollbackResidue.Count -eq 0) `
        'A successful rollback left transaction residue behind.'
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $afterRollback = Invoke-LauncherFixture -Script $fixtureLauncher `
        -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($afterRollback.ToolLog)) `
        'Rollback did not restore the full manifest-covered runtime bundle.'

    $manifestPath = Join-Path $sourceRoot 'build\neura_launcher.payload.json'
    $invalidManifest = [PSCustomObject]@{
        schema = 1
        files = @(
            [PSCustomObject]@{
                path = '..\escape.dll'
                length = 1
                sha256 = ('a' * 64)
            }
        )
    } | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath $manifestPath -Value $invalidManifest -Encoding UTF8
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $invalidManifestRepair = Invoke-LauncherFixture -Script $fixtureLauncher `
        -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($invalidManifestRepair.ToolLog -match 'build windows --release') `
        'A structurally invalid payload manifest did not self-heal through a rebuild.'

    Remove-Item -LiteralPath (Join-Path $release 'sample_plugin.dll') -Force
    $env:NEURA_TEST_SKIP_PLUGIN = '1'
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $missingPlugin = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 1
    Assert-True ($missingPlugin.ToolLog -match 'build windows --release') 'A missing plugin DLL did not attempt repair.'
    Assert-True ($missingPlugin.Output -match 'did not restore the previously verified payload') 'An unrepaired plugin DLL did not fail closed.'
    $env:NEURA_TEST_SKIP_PLUGIN = $null
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $repairedPlugin = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($repairedPlugin.ToolLog -match 'build windows --release') 'A missing plugin DLL was not repaired on retry.'

    Set-Content -LiteralPath $sourceFile -Value 'void main() { print("changed"); }' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $changed = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($changed.ToolLog -match 'build windows --release') 'Changed source-export input did not force a rebuild.'

    $supportSource = Join-Path $fixtureTools 'NeuraLocalConversationPolicy.ps1'
    Add-Content -LiteralPath $supportSource -Value '# changed' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $supportChanged = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($supportChanged.ToolLog -match 'build windows --release') 'Changed packaged support input did not force a source-export rebuild.'

    $stampPath = Join-Path $sourceRoot 'build\neura_launcher.stamp'
    Set-Content -LiteralPath $stampPath -Value '' -Encoding ASCII -NoNewline
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $emptyStamp = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($emptyStamp.ToolLog -match 'build windows --release') 'A truncated build stamp did not trigger a clean rebuild.'

    Set-Content -LiteralPath (Join-Path $release 'msvcp140.dll') `
        -Value 'forged! msvcp140.dll' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $staleRuntime = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($staleRuntime.ToolLog -match 'build windows --release') 'A modified runtime DLL did not force repair.'
    Assert-True ($staleRuntime.Output.Contains($fakeRedist)) (
        'The rebuild packaged a runtime set other than the verified fixture.' +
        [Environment]::NewLine + $staleRuntime.Output
    )
    foreach ($runtimeName in @(
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll'
    )) {
        $expectedRuntimeHash = (Get-FileHash -LiteralPath (
            Join-Path $fakeRedist $runtimeName
        ) -Algorithm SHA256).Hash
        $packagedRuntimeHash = (Get-FileHash -LiteralPath (
            Join-Path $release $runtimeName
        ) -Algorithm SHA256).Hash
        Assert-True ($packagedRuntimeHash -eq $expectedRuntimeHash) `
            "The rebuild did not refresh $runtimeName from one verified runtime set."
    }

    Set-Content -LiteralPath (Join-Path $release 'neura_api.exe') -Value '' -Encoding ASCII -NoNewline
    $env:NEURA_TEST_SKIP_API = '1'
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $emptyPayload = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 1
    Assert-True ($emptyPayload.ToolLog -match 'build windows --release') 'An empty payload file did not attempt repair.'
    Assert-True ($emptyPayload.Output -match 'incomplete runtime payload') 'An unrepaired empty payload did not fail as incomplete.'

    Remove-Item -LiteralPath (Join-Path $release 'neura_api.exe') -Force
    New-Item -ItemType Directory -Path (Join-Path $release 'neura_api.exe') | Out-Null
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $directoryPayload = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 1
    Assert-True ($directoryPayload.ToolLog -match 'build windows --release') 'A directory in place of a payload file did not attempt repair.'
    Assert-True ($directoryPayload.Output -match 'incomplete runtime payload') 'An unrepaired directory payload did not fail as incomplete.'

    $env:NEURA_TEST_SKIP_API = $null
    Remove-Item -LiteralPath (Join-Path $release 'neura_api.exe') -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath (Join-Path $release 'neura_api.exe') -Value 'fixture' -Encoding ASCII

    Set-Content -LiteralPath (Join-Path $sourceRoot '.gitignore') -Encoding ASCII -Value @(
        '/build/',
        '/fake-bin/',
        '/fake-program-files/',
        '/assets/ignored.fixture'
    )
    $readmePath = Join-Path $sourceRoot 'README.md'
    Set-Content -LiteralPath $readmePath -Value 'unrelated fixture' -Encoding ASCII
    Remove-Item -LiteralPath (Join-Path $fakeBin 'git.cmd') -Force
    Invoke-QuietNative { & git -C $sourceRoot init } | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Could not initialize the launcher Git fixture.'
    Invoke-QuietNative { & git -C $sourceRoot add -- . } | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Could not stage the launcher Git fixture.'
    Invoke-QuietNative {
        & git -C $sourceRoot -c user.name='Neura CI' `
            -c user.email='neura-ci@example.invalid' commit -m 'fixture baseline'
    } | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Could not commit the launcher Git fixture.'

    Remove-Item -LiteralPath $stampPath -Force
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $gitInitial = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($gitInitial.ToolLog -match 'build windows --release') 'The initial Git fingerprint did not build.'

    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $gitUnchanged = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($gitUnchanged.ToolLog)) 'An unchanged Git worktree rebuilt unexpectedly.'

    Add-Content -LiteralPath $readmePath -Value 'unrelated tracked change' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $sourceRoot 'notes.txt') -Value 'unrelated untracked change' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $unrelated = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($unrelated.ToolLog)) 'Unrelated Git files incorrectly forced a rebuild.'

    $ignoredAsset = Join-Path $sourceRoot 'assets\ignored.fixture'
    New-Item -ItemType Directory -Path (Split-Path -Parent $ignoredAsset) -Force | Out-Null
    Set-Content -LiteralPath $ignoredAsset -Value 'ignored but packaged' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $ignored = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($ignored.ToolLog -match 'build windows --release') 'An ignored packaged asset did not force a rebuild.'
    Remove-Item -LiteralPath $ignoredAsset -Force
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $ignoredRemoved = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($ignoredRemoved.ToolLog -match 'build windows --release') 'Removing an ignored packaged asset did not force a rebuild.'

    Set-Content -LiteralPath $sourceFile -Value 'void main() { print("unstaged"); }' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $unstaged = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($unstaged.ToolLog -match 'build windows --release') 'An unstaged source change did not force a rebuild.'

    Set-Content -LiteralPath $sourceFile -Value 'void main() { print("staged"); }' -Encoding ASCII
    Invoke-QuietNative { & git -C $sourceRoot add -- lib/main.dart } | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Could not stage the launcher source fixture.'
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $staged = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($staged.ToolLog -match 'build windows --release') 'A staged source change did not force a rebuild.'

    $untrackedSource = Join-Path $sourceRoot 'lib\untracked.dart'
    Set-Content -LiteralPath $untrackedSource -Value 'const fixture = true;' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $untracked = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($untracked.ToolLog -match 'build windows --release') 'An untracked source input did not force a rebuild.'

    Set-Content -LiteralPath $sourceFile -Value 'void main() { print("changed"); }' -Encoding ASCII
    Invoke-QuietNative { & git -C $sourceRoot add -- lib/main.dart } | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Could not restore the tracked launcher source fixture.'
    Remove-Item -LiteralPath $untrackedSource -Force
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $restored = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($restored.ToolLog -match 'build windows --release') 'Returning to clean source content left a stale dirty build current.'

    $mutexSuffix = (Get-TestTextSha256 -Text (
        (Resolve-Path -LiteralPath $sourceRoot).Path.ToUpperInvariant()
    )).Substring(0, 24)
    $fixtureMutex = [Threading.Mutex]::new(
        $false,
        "NeuraCompanionLauncher-$mutexSuffix"
    )
    $fixtureMutexHeld = $fixtureMutex.WaitOne(0)
    Assert-True $fixtureMutexHeld 'Could not acquire the launcher contention fixture mutex.'
    Set-Content -LiteralPath $sourceFile -Value 'void main() { print("mutex"); }' -Encoding ASCII
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $contended = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($contended.ToolLog)) 'A contended launcher ran build tools.'
    Assert-True ($contended.Output -match 'already in progress') 'A contended launcher did not explain the no-op.'
    $fixtureMutex.ReleaseMutex()
    $fixtureMutexHeld = $false
    $fixtureMutex.Dispose()
    $fixtureMutex = $null

    $fixtureBuildLock = [IO.File]::Open(
        (Join-Path $sourceRoot 'build\neura_launcher.lock'),
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $crossSessionContention = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ([string]::IsNullOrWhiteSpace($crossSessionContention.ToolLog)) 'A cross-session build lock still allowed build tools to run.'
    Assert-True ($crossSessionContention.Output -match 'already in progress') 'A cross-session build lock did not explain the no-op.'
    $fixtureBuildLock.Dispose()
    $fixtureBuildLock = $null

    Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    $afterContention = Invoke-LauncherFixture -Script $fixtureLauncher -ToolLog $toolLog -ExpectedExit 0
    Assert-True ($afterContention.ToolLog -match 'build windows --release') 'The source change was not built after launcher contention cleared.'
} finally {
    if ($fixtureMutexHeld -and $fixtureMutex) {
        $fixtureMutex.ReleaseMutex()
    }
    if ($fixtureMutex) {
        $fixtureMutex.Dispose()
    }
    if ($fixtureBuildLock) {
        $fixtureBuildLock.Dispose()
    }
    $env:PATH = $oldPath
    $env:NEURA_TEST_TOOL_LOG = $oldToolLog
    $env:NEURA_TEST_FAIL_BUILD = $oldFailBuild
    $env:NEURA_TEST_SKIP_API = $oldSkipApi
    $env:NEURA_TEST_SKIP_PLUGIN = $oldSkipPlugin
    $env:ProgramFiles = $oldProgramFiles
    [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $oldProgramFilesX86)
    Remove-Item -LiteralPath $batchRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $sourceRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ($toolLog) {
        Remove-Item -LiteralPath $toolLog -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Neura launcher syntax, freshness, payload, path, and exit-code contracts passed.'
exit 0
