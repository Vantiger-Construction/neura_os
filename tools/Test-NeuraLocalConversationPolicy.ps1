Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NeuraLocalConversationPolicy.ps1')
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    try { & $Action | Out-Null } catch { return }
    throw $Message
}
Assert-True ((Get-NeuraLocalConversationProfile 8GB 3GB).Model -eq 'Qwen3.5-2B') '8 GB selection failed.'
Assert-True ((Get-NeuraLocalConversationProfile 8GB 2GB).Model -eq 'Qwen3.5-0.8B') 'Low free memory must select the small model.'
Assert-True ((Get-NeuraLocalConversationProfile 4GB 1.75GB).Model -eq 'Qwen3.5-0.8B') '4 GB selection failed.'
Assert-Throws { Get-NeuraLocalConversationProfile 4GB 1GB } 'Insufficient memory must block startup.'
Assert-Throws { Get-NeuraLocalConversationProfile 0 0 } 'Unknown memory must block startup.'
Assert-Throws { Get-NeuraLocalConversationProfile 4GB 5GB } 'Invalid memory must block startup.'
Assert-True ((ConvertTo-NeuraLocalConversationArgument 'a b') -ceq '"a b"') 'Space quoting failed.'
Assert-True ((ConvertTo-NeuraLocalConversationArgument 'a"b') -ceq '"a\"b"') 'Quote escaping failed.'
Assert-True ((ConvertTo-NeuraLocalConversationArgument 'C:\a\') -ceq '"C:\a\\"') 'Trailing slash escaping failed.'
$temp = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($temp, 'asset fixture')
    $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-NeuraLocalConversationHash $temp $hash
    Assert-Throws { Assert-NeuraLocalConversationHash $temp ('0' * 64) } 'An unverified asset must block startup.'
} finally { Remove-Item -LiteralPath $temp -Force }
$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Start-NeuraLocalConversation.ps1'), [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'The launcher has PowerShell syntax errors.'
if ($env:OS -eq 'Windows_NT') {
    if (-not ('NeuraLocalConversationJob' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'NeuraLocalConversationProcess.cs')
    }
    $job = [NeuraLocalConversationJob]::new()
    $process = [Diagnostics.Process]::new()
    try {
        $process.StartInfo.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $process.StartInfo.Arguments = '/d /c ping -n 60 127.0.0.1 > nul'
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        [void]$process.Start()
        $job.Attach($process)
        $job.Dispose()
        Assert-True ($process.WaitForExit(5000)) 'Closing ownership must terminate the attached child.'
    } finally {
        $job.Dispose()
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}
Write-Host 'Local conversation memory policy, asset checks, quoting, syntax and process ownership passed.'
