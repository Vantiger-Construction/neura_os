Set-StrictMode -Version Latest

function Get-NeuraLocalConversationProfile {
    param(
        [Parameter(Mandatory)][UInt64]$TotalBytes,
        [Parameter(Mandatory)][UInt64]$AvailableBytes
    )
    if ($TotalBytes -eq 0 -or $AvailableBytes -gt $TotalBytes) {
        throw 'Unable to determine available physical memory.'
    }
    # These are conservative admission thresholds, not measured peak usage.
    if ($TotalBytes -ge 7GB -and $AvailableBytes -ge 3GB) {
        return [pscustomobject]@{
            Model = 'Qwen3.5-2B'; FileName = 'Qwen3.5-2B-Q4_K_M.gguf'
            Sha256 = 'aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223'
            Revision = '802854bfd388ed92748de119df31327962811548'
            Threads = 2; ContextTokens = 2048; ReplyTokens = 256
        }
    }
    if ($TotalBytes -ge 3GB -and $AvailableBytes -ge 1.75GB) {
        return [pscustomobject]@{
            Model = 'Qwen3.5-0.8B'; FileName = 'Qwen3.5-0.8B-Q4_K_M.gguf'
            Sha256 = 'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517'
            Revision = 'ed4bdcdbcce9f095bb49e8759176c64e45fa294b'
            Threads = 2; ContextTokens = 2048; ReplyTokens = 256
        }
    }
    throw 'Not enough free physical memory. Close other apps before starting a local model.'
}

function Assert-NeuraLocalConversationHash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'A required local model or runtime archive is missing. Download it explicitly using the setup guide.'
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Expected) {
        throw 'Local asset SHA-256 does not match the reviewed asset. Nothing was started.'
    }
}

function ConvertTo-NeuraLocalConversationArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    # Quote according to Windows CommandLineToArgvW rules; never use a shell.
    if ($Value.Contains([char]0)) { throw 'Invalid native argument.' }
    $quoted = [System.Text.StringBuilder]::new()
    [void]$quoted.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$quoted.Append([char]'\', (2 * $slashes + 1))
        } else {
            [void]$quoted.Append([char]'\', $slashes)
        }
        [void]$quoted.Append($character)
        $slashes = 0
    }
    [void]$quoted.Append([char]'\', (2 * $slashes))
    [void]$quoted.Append('"')
    $quoted.ToString()
}
