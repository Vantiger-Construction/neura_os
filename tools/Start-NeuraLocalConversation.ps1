[CmdletBinding()]
param(
    [string]$LlamaArchivePath,
    [string]$ModelsDirectory,
    [string]$ChatExecutablePath,
    [switch]$AllowSessionText,
    [switch]$PreflightOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NeuraLocalConversationPolicy.ps1')
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
    throw 'This launcher requires 64-bit Windows PowerShell.'
}
$memory = Get-CimInstance Win32_OperatingSystem
$profile = Get-NeuraLocalConversationProfile `
    -TotalBytes ([UInt64]$memory.TotalVisibleMemorySize * 1024) `
    -AvailableBytes ([UInt64]$memory.FreePhysicalMemory * 1024)
if ($PreflightOnly) { $profile; return }
if (-not $AllowSessionText) {
    throw 'Use -AllowSessionText to permit only the text you type in this terminal for this session.'
}
if ([string]::IsNullOrWhiteSpace($LlamaArchivePath) -or [string]::IsNullOrWhiteSpace($ModelsDirectory)) {
    throw 'Provide the local runtime archive and models directory from docs/NEURA_OFFLINE_CONVERSATION.md.'
}
if ([string]::IsNullOrWhiteSpace($ChatExecutablePath)) {
    $ChatExecutablePath = Join-Path $PSScriptRoot '..\rust\target\release\neura_local_chat.exe'
}
if (-not (Test-Path -LiteralPath $ChatExecutablePath -PathType Leaf)) {
    throw 'Build neura_local_chat with Cargo before starting this prototype.'
}
$ChatExecutablePath = (Resolve-Path -LiteralPath $ChatExecutablePath).ProviderPath
$modelPath = Join-Path $ModelsDirectory $profile.FileName
Assert-NeuraLocalConversationHash -Path $modelPath -Expected $profile.Sha256
$modelPath = (Resolve-Path -LiteralPath $modelPath).ProviderPath
# Official llama.cpp b11429 CPU x64 archive; no automatic download or updates.
Assert-NeuraLocalConversationHash -Path $LlamaArchivePath `
    -Expected '1283323272b04cd07905816a597a0da810918102de958f4ff6f7bbaa70ed2efe'
if (-not ('NeuraLocalConversationJob' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'NeuraLocalConversationProcess.cs')
}
$foreground = [NeuraLocalConversationJob]::GetForegroundWindow()
if ($foreground -eq [IntPtr]::Zero) { throw 'Start this prototype from a foreground terminal.' }
$runtimeRoot = Join-Path ([IO.Path]::GetTempPath()) ('neura-local-runtime-' + [Guid]::NewGuid().ToString('N'))
$server = $null
$chat = $null
$job = $null
$http = $null
$token = $null
$rng = $null
$bytes = New-Object byte[] 32
try {
    Expand-Archive -LiteralPath $LlamaArchivePath -DestinationPath $runtimeRoot
    $executables = @(Get-ChildItem -LiteralPath $runtimeRoot -Filter 'llama-server.exe' -Recurse -File)
    if ($executables.Count -ne 1) { throw 'The reviewed archive must contain exactly one llama-server.exe.' }
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $token = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { $port = $listener.LocalEndpoint.Port } finally { $listener.Stop() }
    $job = [NeuraLocalConversationJob]::new()
    $arguments = @(
        '--model', $modelPath, '--host', '127.0.0.1', '--port', "$port",
        '--alias', 'neura-local', '--ctx-size', '2048', '--parallel', '1',
        '--threads', '2', '--threads-batch', '2', '--threads-http', '1',
        '--batch-size', '128', '--ubatch-size', '128', '--n-gpu-layers', '0',
        '--offline', '--no-mmproj', '--no-webui', '--no-agent', '--no-ui-mcp-proxy',
        '--no-slots', '--no-cache-prompt', '--no-context-shift', '--log-disable',
        '--chat-template-kwargs', '{"enable_thinking":false}'
    )
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $executables[0].FullName
    $info.WorkingDirectory = $executables[0].DirectoryName
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Arguments = (($arguments | ForEach-Object { ConvertTo-NeuraLocalConversationArgument $_ }) -join ' ')
    $info.EnvironmentVariables.Clear()
    $info.EnvironmentVariables['SystemRoot'] = $env:SystemRoot
    $info.EnvironmentVariables['TEMP'] = $runtimeRoot
    $info.EnvironmentVariables['TMP'] = $runtimeRoot
    $info.EnvironmentVariables['LLAMA_API_KEY'] = $token
    $server = [Diagnostics.Process]::new()
    $server.StartInfo = $info
    if (-not $server.Start()) { throw 'The local model runtime could not start.' }
    $job.Attach($server)
    $server.StandardInput.Close()
    # Drain into discarded callbacks, never into transcripts or log files.
    $server.BeginOutputReadLine()
    $server.BeginErrorReadLine()
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $http = [Net.Http.HttpClient]::new($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(2)
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $ready = $false
    Write-Host "Loading $($profile.Model). Conversation stays in this terminal session."
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($server.HasExited) { throw 'The local model runtime exited before readiness.' }
        if ([NeuraLocalConversationJob]::GetForegroundWindow() -ne $foreground) {
            throw 'Session stopped because the terminal left the foreground.'
        }
        # Establish socket ownership before sending any credential or text.
        $owned = @(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $port `
            -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -eq $server.Id })
        if ($owned.Count -eq 1) {
            try {
                $response = $http.GetAsync("http://127.0.0.1:$port/health").GetAwaiter().GetResult()
                try { $ready = $response.IsSuccessStatusCode } finally { $response.Dispose() }
            } catch { $ready = $false }
            if ($ready) { break }
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw 'Local model readiness timed out. No conversation was sent.' }
    $chatInfo = [Diagnostics.ProcessStartInfo]::new()
    $chatInfo.FileName = $ChatExecutablePath
    $chatInfo.UseShellExecute = $false
    $chatInfo.Arguments = "--allow-session-text --port $port"
    $chatInfo.EnvironmentVariables.Clear()
    $chatInfo.EnvironmentVariables['SystemRoot'] = $env:SystemRoot
    $chatInfo.EnvironmentVariables['NEURA_LOCAL_SESSION_TOKEN'] = $token
    $chat = [Diagnostics.Process]::new()
    $chat.StartInfo = $chatInfo
    if (-not $chat.Start()) { throw 'The Rust local conversation prototype could not start.' }
    $job.Attach($chat)
    while (-not $chat.WaitForExit(100)) {
        if ($server.HasExited -or [NeuraLocalConversationJob]::GetForegroundWindow() -ne $foreground) {
            throw 'Local session ended: its server stopped or the terminal left the foreground.'
        }
    }
    if ($chat.ExitCode -ne 0) { throw 'The Rust local conversation prototype did not complete successfully.' }
} finally {
    if ($job) { $job.Dispose() }
    foreach ($process in @($chat, $server)) {
        if ($process) {
            try {
                if (-not $process.HasExited) { $process.Kill() }
                [void]$process.WaitForExit(5000)
            } catch {
                # Start can fail before a Process has an associated handle.
                # Continue disposing other owners and removing runtime files.
            } finally { $process.Dispose() }
        }
    }
    if ($http) { $http.Dispose() }
    if ($rng) { $rng.Dispose() }
    [Array]::Clear($bytes, 0, $bytes.Length)
    $token = $null
    if (Test-Path -LiteralPath $runtimeRoot) { Remove-Item -LiteralPath $runtimeRoot -Recurse -Force }
}
