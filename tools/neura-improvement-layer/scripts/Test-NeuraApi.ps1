[CmdletBinding()]
param(
  [string[]]$Urls = @('http://127.0.0.1:8000/health','http://127.0.0.1:8799/health')
)
$ErrorActionPreference = 'Continue'
foreach ($url in $Urls) {
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
    $sw.Stop()
    [pscustomobject]@{ Url=$url; Online=$true; Status=$response.StatusCode; Milliseconds=$sw.ElapsedMilliseconds }
  } catch {
    [pscustomobject]@{ Url=$url; Online=$false; Status=$null; Milliseconds=$null; Error=$_.Exception.Message }
  }
}
