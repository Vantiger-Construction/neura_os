#Requires -Version 5.1
<#
.SYNOPSIS
Collects content-free milestone 2 evidence for the pinned local model.

.DESCRIPTION
Builds the Neura Engine sidecar and the evidence tool in release mode, then
measures the pinned qwen3:4b-instruct model in your own Ollama: time to first
token, total time, peak memory use, power state, model size and digest, and
how quickly a cancel takes effect.

The tool loads the model several times using only Neura's fixed synthetic
prompts. It never downloads a model, starts Ollama, or records prompt or model
text. Start Ollama yourself first. -ConfirmLocalModel is required.

The JSON report is written to -OutFile (default: a timestamped file in the
current directory). Exit code 2 means the model was unavailable; the report
then says why.

.EXAMPLE
.\tools\Collect-NeuraEngineEvidence.ps1 -ConfirmLocalModel -Runs 3
#>
[CmdletBinding()]
param(
    [switch]$ConfirmLocalModel,
    [ValidateRange(1, 20)]
    [int]$Runs = 3,
    [string]$OutFile = ("neura-engine-evidence-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
)

$ErrorActionPreference = 'Stop'

if (-not $ConfirmLocalModel) {
    [Console]::Error.WriteLine('This loads your installed qwen3:4b-instruct model several times. ' +
        'Nothing is downloaded and no prompt or model text is recorded. ' +
        'Re-run with -ConfirmLocalModel to proceed.')
    exit 64
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $repoRoot 'rust\Cargo.toml'

& cargo build --release --locked --manifest-path $manifest --bin neura_api --bin neura_engine_evidence
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$targetRoot = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $repoRoot 'rust\target' }
$targetDir = Join-Path $targetRoot 'release'
$tool = Join-Path $targetDir 'neura_engine_evidence.exe'
$sidecar = Join-Path $targetDir 'neura_api.exe'

& $tool --confirm-local-model --runs $Runs --sidecar $sidecar --out $OutFile
$code = $LASTEXITCODE
if ($code -eq 0 -or $code -eq 2) {
    Write-Host "Evidence report: $((Resolve-Path -LiteralPath $OutFile).Path)"
}
exit $code
