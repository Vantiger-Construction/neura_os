#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Net.Http

function Resolve-NeuraApiBaseUri {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BaseUrl)

    $candidate = $null
    if (-not ([Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$candidate))) {
        throw 'BaseUrl must be an absolute URI.'
    }
    if ($candidate.Scheme -ne 'http' -or
        $candidate.Host -ne '127.0.0.1' -or
        $candidate.Port -lt 1 -or
        $candidate.UserInfo -or
        $candidate.Query -or
        $candidate.Fragment) {
        throw 'BaseUrl must be http://127.0.0.1:<port>/v1 with no credentials, query, or fragment.'
    }

    $path = $candidate.AbsolutePath.TrimEnd('/')
    if ($path -ne '/v1') {
        throw 'BaseUrl path must be /v1.'
    }

    return [Uri]::new("http://127.0.0.1:$($candidate.Port)/v1/")
}

function Read-NeuraApiToken {
    [CmdletBinding()]
    param([Security.SecureString]$Token)

    if ($null -ne $Token -and $Token.Length -gt 0) {
        return $Token
    }
    if (-not ([string]::IsNullOrWhiteSpace($env:NEURA_LOCAL_API_TOKEN))) {
        return ConvertTo-SecureString $env:NEURA_LOCAL_API_TOKEN -AsPlainText -Force
    }
    return Read-Host 'Neura session token' -AsSecureString
}

function ConvertFrom-NeuraSecureToken {
    param([Parameter(Mandatory)][Security.SecureString]$Token)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Invoke-NeuraApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Uri]$BaseUri,
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_/-]+$')][string]$Path,
        [Security.SecureString]$Token,
        [AllowNull()][string]$JsonBody,
        [switch]$OmitAuthorization,
        [AllowNull()][string]$Origin
    )

    $relativePath = $Path.TrimStart('/')
    $requestUri = [Uri]::new($BaseUri, $relativePath)
    if ($requestUri.Host -ne '127.0.0.1' -or $requestUri.Port -ne $BaseUri.Port) {
        throw 'Request path escaped the loopback API origin.'
    }

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(10)
    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::new($Method),
        $requestUri
    )
    $response = $null
    $plainToken = $null

    try {
        if (-not $OmitAuthorization) {
            if ($null -eq $Token -or $Token.Length -eq 0) {
                throw 'A session token is required.'
            }
            $plainToken = ConvertFrom-NeuraSecureToken $Token
            $request.Headers.TryAddWithoutValidation(
                'Authorization',
                "Bearer $plainToken"
            ) | Out-Null
        }
        if (-not ([string]::IsNullOrWhiteSpace($Origin))) {
            $request.Headers.TryAddWithoutValidation('Origin', $Origin) | Out-Null
        }
        if ($null -ne $JsonBody) {
            $request.Content = [System.Net.Http.StringContent]::new(
                $JsonBody,
                [Text.Encoding]::UTF8,
                'application/json'
            )
        }

        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $body = $null
        if (-not ([string]::IsNullOrWhiteSpace($text))) {
            try {
                $body = $text | ConvertFrom-Json
            } catch {
                $body = $text
            }
        }
        return [PSCustomObject]@{
            StatusCode   = [int]$response.StatusCode
            Body         = $body
            NetworkError = $false
            ErrorType    = $null
        }
    } catch {
        return [PSCustomObject]@{
            StatusCode   = $null
            Body         = $null
            NetworkError = $true
            ErrorType    = $_.Exception.GetType().Name
        }
    } finally {
        $plainToken = $null
        if ($null -ne $response) { $response.Dispose() }
        $request.Dispose()
        $client.Dispose()
    }
}

function New-NeuraProposalJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]{1,64}$')]
        [string]$RequestId,
        [Parameter(Mandatory)][ValidateSet('open_room', 'set_tone', 'sync_journal')]
        [string]$Action,
        [AllowNull()][string]$Value
    )

    $arguments = switch ($Action) {
        'open_room' {
            $rooms = @(
                'penthouse', 'reflection_bay', 'joy_lounge', 'mood_den',
                'dream_atrium', 'legacy_vault'
            )
            if ($rooms -notcontains $Value) {
                throw "Value must be a known room: $($rooms -join ', ')."
            }
            @{ room = $Value }
        }
        'set_tone' {
            $tones = @(
                'strategist', 'calm_wellness', 'warm_companion',
                'cinematic_guide', 'quiet_private'
            )
            if ($tones -notcontains $Value) {
                throw "Value must be a known tone: $($tones -join ', ')."
            }
            @{ tone = $Value }
        }
        'sync_journal' {
            if (-not ([string]::IsNullOrWhiteSpace($Value))) {
                throw 'sync_journal does not accept a value.'
            }
            @{}
        }
    }

    return @{
        request_id = $RequestId
        action     = $Action
        arguments  = $arguments
    } | ConvertTo-Json -Compress -Depth 4
}

Export-ModuleMember -Function @(
    'Resolve-NeuraApiBaseUri',
    'Read-NeuraApiToken',
    'Invoke-NeuraApiRequest',
    'New-NeuraProposalJson'
)
