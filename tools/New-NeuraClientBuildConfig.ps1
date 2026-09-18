#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$SupabaseUrl = $env:NEURA_SUPABASE_URL,
    [string]$PublishableKey = $env:NEURA_SUPABASE_PUBLISHABLE_KEY,
    [switch]$RequireConfiguration
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -and [string]::IsNullOrWhiteSpace($PublishableKey)) {
    if ($RequireConfiguration) { throw 'Configured build requested but Supabase public settings are missing.' }
    # Do not reuse a define file inherited from the runner's environment.
    if ($env:GITHUB_ENV) {
        @('NEURA_DART_DEFINE_FILE=', 'NEURA_CLIENT_CONFIG_SHA256=', 'NEURA_CLIENT_PROJECT_URL=') |
            Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    }
    if ($env:GITHUB_OUTPUT) { 'configured=false' | Out-File $env:GITHUB_OUTPUT -Encoding utf8 -Append }
    Write-Host 'Building the existing local-only configuration.'
    return
}
if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($PublishableKey)) {
    throw 'Both NEURA_SUPABASE_URL and NEURA_SUPABASE_PUBLISHABLE_KEY are required.'
}
[Uri]$uri = $null
if (-not [Uri]::TryCreate($SupabaseUrl, [UriKind]::Absolute, [ref]$uri) -or
    $uri.Scheme -ne 'https' -or $uri.Host -notmatch '^[a-z0-9]{20}\.supabase\.co$' -or
    -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne '/') {
    throw 'Supabase URL must be an HTTPS project origin without credentials, path or query.'
}
if ($PublishableKey -notmatch '\Asb_publishable_[A-Za-z0-9_-]+\z') {
    throw 'Only a public sb_publishable_ key is allowed in a client build; secret and service-role keys are forbidden.'
}
if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::add-mask::$PublishableKey" }
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$config = [ordered]@{ SUPABASE_URL = $uri.GetLeftPart([UriPartial]::Authority); SUPABASE_ANON_KEY = $PublishableKey }
$json = $config | ConvertTo-Json
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($env:GITHUB_ENV) {
    "NEURA_DART_DEFINE_FILE=$OutputPath" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    "NEURA_CLIENT_CONFIG_SHA256=$hash" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    "NEURA_CLIENT_PROJECT_URL=$($config.SUPABASE_URL)" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
}
if ($env:GITHUB_OUTPUT) { 'configured=true' | Out-File $env:GITHUB_OUTPUT -Encoding utf8 -Append }
Write-Host "Public client configuration prepared for $($uri.Host); SHA256 $hash"
