#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$BaseUrl = $env:NEURA_LOCAL_API_URL,
    [Security.SecureString]$Token,
    [string]$EvidencePath = (Join-Path (Get-Location) (
        'neura-local-api-{0}.evidence.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    ))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'NeuraLocalApi.psm1') -Force

$startedAt = (Get-Date).ToUniversalTime().ToString('o')
$checks = [Collections.Generic.List[object]]::new()
$resultState = 'failed'
$failure = $null

function Add-LiveCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Expected,
        [AllowNull()][object]$Observed
    )

    $checks.Add([PSCustomObject][ordered]@{
        name       = $Name
        passed     = $Passed
        expected   = $Expected
        observed   = $Observed
        observed_at = (Get-Date).ToUniversalTime().ToString('o')
    })
    if ($Passed) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        return
    }
    throw "Verification failed: $Name"
}

function Confirm-LiveObservation {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Expected
    )

    $answer = Read-Host "$Prompt Type YES to record the observation"
    Add-LiveCheck -Name $Name -Passed ($answer -ceq 'YES') `
        -Expected $Expected -Observed $(if ($answer -ceq 'YES') { 'confirmed' } else { 'not confirmed' })
}

function Get-FinalReceipt {
    param(
        [Parameter(Mandatory)][Uri]$BaseUri,
        [Parameter(Mandatory)][Security.SecureString]$SessionToken,
        [Parameter(Mandatory)][string]$ProposalId
    )

    $last = $null
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $last = Invoke-NeuraApiRequest -BaseUri $BaseUri -Method GET `
            -Path "proposals/$ProposalId" -Token $SessionToken
        if ($last.NetworkError -or $last.StatusCode -ne 200) { return $last }
        if ($last.Body.status -notin @('pending', 'reviewing')) { return $last }
        Start-Sleep -Milliseconds 500
    }
    return $last
}

function Test-ListenerStopped {
    param(
        [Parameter(Mandatory)][Uri]$BaseUri,
        [Parameter(Mandatory)][Security.SecureString]$SessionToken
    )

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $probe = Invoke-NeuraApiRequest -BaseUri $BaseUri -Method GET `
            -Path health -Token $SessionToken
        if ($probe.NetworkError) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Read-ReenabledSession {
    param([Parameter(Mandatory)][string]$Label)

    Write-Host ''
    Write-Host "${Label}: reopen Settings -> Local app API, enable it, and copy the new values."
    $newUrl = Read-Host 'New API address (including /v1)'
    $newToken = Read-Host 'New Neura session token' -AsSecureString
    return [PSCustomObject]@{
        BaseUri = Resolve-NeuraApiBaseUri $newUrl
        Token   = $newToken
    }
}

try {
    Write-Host 'Neura Local App API live verification' -ForegroundColor Cyan
    Write-Host 'No token or private Neura content will be written to evidence.'
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        $BaseUrl = Read-Host 'API address shown by Neura (including /v1)'
    }
    $baseUri = Resolve-NeuraApiBaseUri $BaseUrl
    $sessionToken = Read-NeuraApiToken $Token

    Confirm-LiveObservation `
        -Name 'initial_room_is_penthouse' `
        -Prompt 'Put Neura in Penthouse, then confirm the Current room row on the Local app API screen says Penthouse.' `
        -Expected 'The native Current room row shows Penthouse before the proposal.'

    $unauthenticated = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path health -OmitAuthorization
    Add-LiveCheck -Name 'missing_token_rejected' `
        -Passed (-not $unauthenticated.NetworkError -and $unauthenticated.StatusCode -eq 401) `
        -Expected 'HTTP 401' -Observed $unauthenticated.StatusCode

    $wrongToken = ConvertTo-SecureString 'not-the-neura-session-token' -AsPlainText -Force
    $wrong = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path health -Token $wrongToken
    Add-LiveCheck -Name 'wrong_token_rejected' `
        -Passed (-not $wrong.NetworkError -and $wrong.StatusCode -eq 401) `
        -Expected 'HTTP 401' -Observed $wrong.StatusCode

    $browser = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path health -Token $sessionToken -Origin 'https://example.invalid'
    Add-LiveCheck -Name 'browser_origin_rejected' `
        -Passed (-not $browser.NetworkError -and $browser.StatusCode -eq 401) `
        -Expected 'HTTP 401' -Observed $browser.StatusCode

    $health = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path health -Token $sessionToken
    $healthPassed = (
        -not $health.NetworkError -and
        $health.StatusCode -eq 200 -and
        $health.Body.api_version -eq 1 -and
        $health.Body.api_minor_version -ge 1 -and
        $health.Body.status -eq 'ready' -and
        $health.Body.approval_required -eq $true -and
        $health.ApiVersion -eq '1' -and
        -not ([string]::IsNullOrWhiteSpace($health.TraceId))
    )
    Add-LiveCheck -Name 'authenticated_health' -Passed $healthPassed `
        -Expected 'HTTP 200, API v1.1+, trace ID, ready, approval_required=true' `
        -Observed $(if ($health.NetworkError) { 'network_error' } else { $health.StatusCode })

    $capabilities = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path capabilities -Token $sessionToken
    $actions = @($capabilities.Body.actions)
    $contracts = $capabilities.Body.action_contracts
    $capabilitiesPassed = (
        -not $capabilities.NetworkError -and
        $capabilities.StatusCode -eq 200 -and
        $capabilities.Body.approval -eq 'each_action_in_neura' -and
        $capabilities.Body.cloud_ai -eq $false -and
        $capabilities.Body.memory_access -eq $false -and
        $actions.Count -eq 3 -and
        $actions -contains 'open_room' -and
        $actions -contains 'set_tone' -and
        $actions -contains 'sync_journal' -and
        $null -ne $contracts.open_room -and
        $null -ne $contracts.set_tone -and
        $null -ne $contracts.sync_journal -and
        @($contracts.open_room.allowed_values) -contains 'reflection_bay' -and
        $capabilities.Body.limits.body_bytes -eq 4096
    )
    Add-LiveCheck -Name 'capabilities_are_bounded' -Passed $capabilitiesPassed `
        -Expected 'Only three proposal actions; native approval; no cloud AI or memory' `
        -Observed ($actions -join ',')

    $execute = Invoke-NeuraApiRequest -BaseUri $baseUri -Method POST `
        -Path execute -Token $sessionToken -JsonBody '{}'
    Add-LiveCheck -Name 'no_execute_endpoint' `
        -Passed (-not $execute.NetworkError -and $execute.StatusCode -eq 404) `
        -Expected 'HTTP 404' -Observed $execute.StatusCode

    $memory = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path memory -Token $sessionToken
    Add-LiveCheck -Name 'no_memory_endpoint' `
        -Passed (-not $memory.NetworkError -and $memory.StatusCode -eq 404) `
        -Expected 'HTTP 404' -Observed $memory.StatusCode

    $requestId = "live-$([Guid]::NewGuid().ToString('N'))"
    $proposalJson = New-NeuraProposalJson -RequestId $requestId `
        -Action open_room -Value reflection_bay `
        -Capabilities $capabilities.Body
    $proposal = Invoke-NeuraApiRequest -BaseUri $baseUri -Method POST `
        -Path proposals -Token $sessionToken -JsonBody $proposalJson
    $proposalId = if ($null -ne $proposal.Body) { [string]$proposal.Body.id } else { '' }
    $proposalPassed = (
        -not $proposal.NetworkError -and
        $proposal.StatusCode -eq 202 -and
        -not ([string]::IsNullOrWhiteSpace($proposalId)) -and
        $proposal.Body.status -eq 'pending'
    )
    Add-LiveCheck -Name 'proposal_queued_not_executed' -Passed $proposalPassed `
        -Expected 'HTTP 202 with pending content-free receipt' `
        -Observed $(if ($proposal.NetworkError) { 'network_error' } else { "$($proposal.StatusCode):$($proposal.Body.status)" })

    $pending = Invoke-NeuraApiRequest -BaseUri $baseUri -Method GET `
        -Path "proposals/$proposalId" -Token $sessionToken
    Add-LiveCheck -Name 'proposal_remains_pending' `
        -Passed (-not $pending.NetworkError -and $pending.StatusCode -eq 200 -and $pending.Body.status -eq 'pending') `
        -Expected 'Receipt remains pending before native review' `
        -Observed $(if ($pending.NetworkError) { 'network_error' } else { $pending.Body.status })

    $duplicate = Invoke-NeuraApiRequest -BaseUri $baseUri -Method POST `
        -Path proposals -Token $sessionToken -JsonBody $proposalJson
    Add-LiveCheck -Name 'identical_retry_is_idempotent' `
        -Passed (-not $duplicate.NetworkError -and $duplicate.StatusCode -eq 200 -and $duplicate.Body.id -eq $proposalId -and $duplicate.Body.status -eq 'pending') `
        -Expected 'HTTP 200 with the original pending receipt' `
        -Observed $(if ($duplicate.NetworkError) { 'network_error' } else { $duplicate.StatusCode })

    $conflictJson = New-NeuraProposalJson -RequestId $requestId `
        -Action open_room -Value joy_lounge `
        -Capabilities $capabilities.Body
    $conflict = Invoke-NeuraApiRequest -BaseUri $baseUri -Method POST `
        -Path proposals -Token $sessionToken -JsonBody $conflictJson
    Add-LiveCheck -Name 'request_id_reuse_rejected' `
        -Passed (-not $conflict.NetworkError -and $conflict.StatusCode -eq 409 -and $conflict.Body.error -eq 'request_id_reused') `
        -Expected 'HTTP 409 request_id_reused' `
        -Observed $(if ($conflict.NetworkError) { 'network_error' } else { $conflict.StatusCode })

    Confirm-LiveObservation `
        -Name 'pending_proposal_did_not_move_room' `
        -Prompt 'Before touching Review, confirm the Current room row still says Penthouse.' `
        -Expected 'The HTTP proposal alone caused no native room change.'

    Read-Host 'In Neura, select Review for open_room reflection_bay and choose Approve once. Then press Enter here'
    $approved = Get-FinalReceipt -BaseUri $baseUri `
        -SessionToken $sessionToken -ProposalId $proposalId
    Add-LiveCheck -Name 'native_approval_finishes_proposal' `
        -Passed (-not $approved.NetworkError -and $approved.StatusCode -eq 200 -and $approved.Body.status -eq 'finished') `
        -Expected 'Receipt status finished only after visible Approve once' `
        -Observed $(if ($approved.NetworkError) { 'network_error' } else { $approved.Body.status })

    Confirm-LiveObservation `
        -Name 'approved_proposal_moved_room' `
        -Prompt 'Confirm the Current room row now says Reflection Bay.' `
        -Expected 'Native room state changed only after approval.'

    $denyRequestId = "deny-$([Guid]::NewGuid().ToString('N'))"
    $denyJson = New-NeuraProposalJson -RequestId $denyRequestId `
        -Action open_room -Value joy_lounge `
        -Capabilities $capabilities.Body
    $denyProposal = Invoke-NeuraApiRequest -BaseUri $baseUri -Method POST `
        -Path proposals -Token $sessionToken -JsonBody $denyJson
    $denyId = if ($null -ne $denyProposal.Body) { [string]$denyProposal.Body.id } else { '' }
    Add-LiveCheck -Name 'denial_test_queued' `
        -Passed (-not $denyProposal.NetworkError -and $denyProposal.StatusCode -eq 202 -and -not ([string]::IsNullOrWhiteSpace($denyId))) `
        -Expected 'HTTP 202 pending open_room joy_lounge' `
        -Observed $(if ($denyProposal.NetworkError) { 'network_error' } else { $denyProposal.StatusCode })

    Read-Host 'In Neura, select Review for open_room joy_lounge and choose Deny. Then press Enter here'
    $denied = Get-FinalReceipt -BaseUri $baseUri `
        -SessionToken $sessionToken -ProposalId $denyId
    Add-LiveCheck -Name 'native_denial_is_final' `
        -Passed (-not $denied.NetworkError -and $denied.StatusCode -eq 200 -and $denied.Body.status -eq 'denied') `
        -Expected 'Receipt status denied' `
        -Observed $(if ($denied.NetworkError) { 'network_error' } else { $denied.Body.status })

    Confirm-LiveObservation `
        -Name 'denied_proposal_did_not_move_room' `
        -Prompt 'Confirm the Current room row remains Reflection Bay and did not change to Joy Lounge.' `
        -Expected 'Denied action produced no native room change.'

    Read-Host 'Enter Safe Mode in Neura now. Wait for the Local API switch to turn off, then press Enter here'
    $safeModeStopped = Test-ListenerStopped -BaseUri $baseUri -SessionToken $sessionToken
    Add-LiveCheck -Name 'safe_mode_stops_listener' -Passed $safeModeStopped `
        -Expected 'The original loopback listener becomes unreachable' `
        -Observed $(if ($safeModeStopped) { 'unreachable' } else { 'still reachable' })

    $sessionTwo = Read-ReenabledSession 'Leave Safe Mode'
    $oldAfterSafeMode = Invoke-NeuraApiRequest -BaseUri $sessionTwo.BaseUri `
        -Method GET -Path health -Token $sessionToken
    Add-LiveCheck -Name 'safe_mode_revokes_old_token' `
        -Passed (-not $oldAfterSafeMode.NetworkError -and $oldAfterSafeMode.StatusCode -eq 401) `
        -Expected 'Old token receives HTTP 401 on the re-enabled listener' `
        -Observed $(if ($oldAfterSafeMode.NetworkError) { 'network_error' } else { $oldAfterSafeMode.StatusCode })

    $newAfterSafeMode = Invoke-NeuraApiRequest -BaseUri $sessionTwo.BaseUri `
        -Method GET -Path health -Token $sessionTwo.Token
    Add-LiveCheck -Name 'safe_mode_reenable_uses_new_token' `
        -Passed (-not $newAfterSafeMode.NetworkError -and $newAfterSafeMode.StatusCode -eq 200) `
        -Expected 'New token receives HTTP 200' `
        -Observed $(if ($newAfterSafeMode.NetworkError) { 'network_error' } else { $newAfterSafeMode.StatusCode })

    Read-Host 'Minimize or background Neura while the Local app API screen is active. Wait for it to be hidden, then press Enter here'
    $backgroundStopped = Test-ListenerStopped `
        -BaseUri $sessionTwo.BaseUri -SessionToken $sessionTwo.Token
    Add-LiveCheck -Name 'backgrounding_stops_listener' -Passed $backgroundStopped `
        -Expected 'The second loopback listener becomes unreachable' `
        -Observed $(if ($backgroundStopped) { 'unreachable' } else { 'still reachable' })

    $sessionThree = Read-ReenabledSession 'Restore Neura'
    $oldAfterBackground = Invoke-NeuraApiRequest -BaseUri $sessionThree.BaseUri `
        -Method GET -Path health -Token $sessionTwo.Token
    Add-LiveCheck -Name 'backgrounding_revokes_old_token' `
        -Passed (-not $oldAfterBackground.NetworkError -and $oldAfterBackground.StatusCode -eq 401) `
        -Expected 'Previous token receives HTTP 401 on the restored listener' `
        -Observed $(if ($oldAfterBackground.NetworkError) { 'network_error' } else { $oldAfterBackground.StatusCode })

    $finalHealth = Invoke-NeuraApiRequest -BaseUri $sessionThree.BaseUri `
        -Method GET -Path health -Token $sessionThree.Token
    Add-LiveCheck -Name 'restored_session_is_authenticated' `
        -Passed (-not $finalHealth.NetworkError -and $finalHealth.StatusCode -eq 200) `
        -Expected 'Newest token receives HTTP 200' `
        -Observed $(if ($finalHealth.NetworkError) { 'network_error' } else { $finalHealth.StatusCode })

    $resultState = 'passed'
} catch {
    $failure = $_.Exception.Message
    [Console]::Error.WriteLine($failure)
} finally {
    $evidence = [PSCustomObject][ordered]@{
        schema            = 'neura.local_api.live_verification.v1'
        result            = $resultState
        started_at        = $startedAt
        completed_at      = (Get-Date).ToUniversalTime().ToString('o')
        client            = 'powershell-5.1-compatible'
        target            = [PSCustomObject]@{
            host        = '127.0.0.1'
            api_version = 1
        }
        checks            = @($checks)
        secrets_recorded  = $false
        failure           = $failure
    }
    $absoluteEvidencePath = [IO.Path]::GetFullPath($EvidencePath)
    $evidenceDirectory = [IO.Path]::GetDirectoryName($absoluteEvidencePath)
    if (-not ([string]::IsNullOrWhiteSpace($evidenceDirectory)) -and
        -not (Test-Path -LiteralPath $evidenceDirectory)) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    $evidence | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $absoluteEvidencePath -Encoding UTF8
    Write-Host "Evidence: $absoluteEvidencePath"
}

if ($resultState -ne 'passed') { exit 1 }
Write-Host 'All live Local app API checks passed.' -ForegroundColor Green
exit 0
