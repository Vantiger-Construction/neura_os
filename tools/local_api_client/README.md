# Neura Local App API clients

These are small, dependency-free clients for the authenticated Local app API
added in PR #87. They connect only to an address in the exact form
`http://127.0.0.1:<port>/v1`, do not follow redirects or use a proxy, and expose
only health, capabilities, proposal creation, and proposal-status commands.
There is deliberately no approve or execute command.

The PowerShell verifier talks to a real running Neura process over the operating
system loopback socket. It is the release-evidence path outside the Flutter test
harness.

## Before connecting

1. Run the configured Windows build of Neura.
2. Open **Settings -> Local app API**.
3. Enable **Allow local app proposals** and keep that screen visible.
4. Copy the displayed `/v1` address. Keep the displayed token private.

Closing the screen, backgrounding Neura, or entering Safe Mode is expected to
stop the listener and revoke the token. Re-enabling the API creates a new random
port and token.

## PowerShell client

Windows PowerShell 5.1 and PowerShell 7 are supported. When `-Token` is omitted,
the client prompts without echo. The optional `NEURA_LOCAL_API_TOKEN`
environment variable is intended only for short-lived automation and should be
cleared immediately afterward.

```powershell
$client = '.\tools\local_api_client\powershell\Neura-LocalApi.ps1'
$url = 'http://127.0.0.1:PORT/v1'

& $client health -BaseUrl $url
& $client capabilities -BaseUrl $url
& $client propose -BaseUrl $url -Action open_room `
  -Value reflection_bay -RequestId my-client-001
& $client status -BaseUrl $url -ProposalId '<id from the receipt>'
```

Proposal values are restricted to Neura's current room and tone allowlists.
`sync_journal` accepts no value and still requires Neura's visible confirmation:

```powershell
& $client propose -BaseUrl $url -Action sync_journal `
  -RequestId my-client-sync-001
```

## Dart client

The Dart client uses only `dart:io` and runs from the repository's existing Dart
SDK. It also prompts for the token without echo when the environment variable is
not set.

```powershell
$dartClient = '.\tools\local_api_client\dart\neura_local_api_client.dart'
$env:NEURA_LOCAL_API_URL = 'http://127.0.0.1:PORT/v1'
$env:NEURA_LOCAL_API_TOKEN = '<session token>'

dart run $dartClient health
dart run $dartClient capabilities
dart run $dartClient propose --action set_tone --value warm_companion `
  --request-id dart-client-001
dart run $dartClient status --id '<id from the receipt>'

Remove-Item Env:NEURA_LOCAL_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:NEURA_LOCAL_API_URL -ErrorAction SilentlyContinue
```

The Dart source is portable, but the API is not cross-device: the client and
Neura must run on the same OS instance because `127.0.0.1` is device-local. Do
not change the listener or client to `0.0.0.0`, a LAN address, or a remote host.

## Live verification and evidence

Start in Penthouse, enable the API, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\tools\local_api_client\powershell\Verify-NeuraLocalApi.ps1 `
  -BaseUrl 'http://127.0.0.1:PORT/v1' `
  -EvidencePath '.\local-api-live.evidence.json'
```

The verifier pauses only where a human must observe or act in Neura. It checks:

| Boundary | Live observation |
| --- | --- |
| Authentication | Missing and wrong tokens return 401; the current token returns API v1 health |
| Native-client boundary | A browser `Origin` is rejected |
| Capability boundary | Only `open_room`, `set_tone`, and `sync_journal` are advertised; cloud AI and memory are false |
| No direct execution | `/v1/execute` and `/v1/memory` return 404 |
| Proposal handling | A proposal starts pending, an identical retry shares its receipt, and conflicting ID reuse returns 409 |
| Visible approval | The native **Current room** row stays on Penthouse before review; **Approve once** finishes the receipt and changes it to Reflection Bay |
| Visible denial | **Deny** finalizes the receipt as denied and leaves the native room row on Reflection Bay |
| Safe Mode revocation | The listener becomes unreachable; after re-enable, the old token returns 401 and the new token works |
| Background revocation | The listener becomes unreachable again; after restore, the prior token returns 401 and the newest token works |

The JSON evidence contains timestamps, expected and observed public statuses, and
manual observation flags. It never records a bearer token, journal content,
memory, files, provider credentials, or microphone data. Evidence files match
`*.evidence.json` and are ignored by Git.

This verification intentionally uses a visible `open_room` proposal rather than
`sync_journal`, avoiding cloud and journal side effects during the proof.
The manual room observations are necessary: adding an HTTP state or approval
endpoint just for automation would weaken the boundary being tested.

## Pre-merge checks

Run these static checks in addition to the live pass:

```powershell
Get-ChildItem '.\tools\local_api_client\powershell\*.ps*1' | ForEach-Object {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $_.FullName, [ref]$tokens, [ref]$errors
  ) | Out-Null
  if ($errors.Count) { $errors | Format-List; exit 1 }
}

dart format --output=none --set-exit-if-changed `
  .\tools\local_api_client\dart\neura_local_api_client.dart
dart analyze .\tools\local_api_client\dart\neura_local_api_client.dart
```

Exit codes for both command clients are `0` for a 2xx response, `2` for invalid
client input, `3` for a non-2xx API response, and `4` for a network failure.
