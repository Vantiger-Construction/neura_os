#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('health', 'capabilities', 'propose', 'status')]
    [string]$Command,
    [string]$BaseUrl = $env:NEURA_LOCAL_API_URL,
    [Security.SecureString]$Token,
    [ValidateSet('open_room', 'set_tone', 'sync_journal')]
    [string]$Action,
    [AllowNull()][string]$Value,
    [ValidatePattern('^[A-Za-z0-9_-]{1,64}$')]
    [string]$RequestId,
    [ValidatePattern('^[A-Za-z0-9_-]{1,128}$')]
    [string]$ProposalId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'NeuraLocalApi.psm1') -Force

try {
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        throw 'Pass -BaseUrl or set NEURA_LOCAL_API_URL.'
    }
    $baseUri = Resolve-NeuraApiBaseUri $BaseUrl
    $sessionToken = Read-NeuraApiToken $Token
    $method = 'GET'
    $path = $Command
    $body = $null

    switch ($Command) {
        'propose' {
            if ([string]::IsNullOrWhiteSpace($Action)) {
                throw '-Action is required for propose.'
            }
            if ([string]::IsNullOrWhiteSpace($RequestId)) {
                $RequestId = "ps-$([Guid]::NewGuid().ToString('N'))"
            }
            $method = 'POST'
            $path = 'proposals'
            $body = New-NeuraProposalJson `
                -RequestId $RequestId `
                -Action $Action `
                -Value $Value
        }
        'status' {
            if ([string]::IsNullOrWhiteSpace($ProposalId)) {
                throw '-ProposalId is required for status.'
            }
            $path = "proposals/$ProposalId"
        }
    }

    $result = Invoke-NeuraApiRequest `
        -BaseUri $baseUri `
        -Method $method `
        -Path $path `
        -Token $sessionToken `
        -JsonBody $body

    [PSCustomObject]@{
        command       = $Command
        status_code   = $result.StatusCode
        body          = $result.Body
        network_error = $result.NetworkError
        error_type    = $result.ErrorType
    } | ConvertTo-Json -Depth 8

    if ($result.NetworkError) { exit 4 }
    if ($result.StatusCode -lt 200 -or $result.StatusCode -ge 300) { exit 3 }
    exit 0
} catch {
    [Console]::Error.WriteLine("Neura local API client: $($_.Exception.Message)")
    exit 2
}
