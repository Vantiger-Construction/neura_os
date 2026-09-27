#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('windows', 'android')][string]$Platform,
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$BuildVolume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RequiredEnvironmentValue {
    param([Parameter(Mandatory)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment value $Name is missing."
    }
    return $value.Trim()
}

function Get-HttpStatusCode {
    param([Parameter(Mandatory)]$ErrorRecord)

    $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ($null -eq $responseProperty) {
        return $null
    }
    $response = $responseProperty.Value
    if ($null -eq $response -or $null -eq $response.StatusCode) {
        return $null
    }
    return [int]$response.StatusCode
}

function Invoke-GitHubJson {
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [AllowNull()]$Body
    )

    $parameters = @{
        Method = $Method
        Uri = $Uri
        Headers = $script:GitHubHeaders
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $parameters.Body = $Body | ConvertTo-Json -Depth 10
        $parameters.ContentType = 'application/json'
    }
    return Invoke-RestMethod @parameters
}

function Find-GitHubReleaseAsset {
    param(
        [AllowNull()]$Assets,
        [Parameter(Mandatory)][string]$Name
    )

    # Windows PowerShell 5.1 can preserve an empty top-level JSON array as a
    # nested System.Object[] when command output is captured. Walk arrays
    # explicitly so an empty GitHub assets response stays empty under strict
    # mode instead of being treated as an object without a name property.
    $pending = New-Object System.Collections.Stack
    $pending.Push($Assets)
    while ($pending.Count -gt 0) {
        $candidate = $pending.Pop()
        if ($null -eq $candidate) {
            continue
        }
        if ($candidate -is [System.Array]) {
            foreach ($item in $candidate) {
                $pending.Push($item)
            }
            continue
        }

        $nameProperty = $candidate.PSObject.Properties['name']
        if ($null -eq $nameProperty) {
            throw 'GitHub returned an invalid release assets response.'
        }
        if ([string]$nameProperty.Value -ceq $Name) {
            return $candidate
        }
    }
    return $null
}

function Get-ContentType {
    param([Parameter(Mandatory)][string]$Path)

    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.apk' { return 'application/vnd.android.package-archive' }
        '.json' { return 'application/json' }
        '.txt' { return 'text/plain' }
        '.zip' { return 'application/zip' }
        default { return 'application/octet-stream' }
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SourceChecksums {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ChecksumPath
    )

    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $lines = @(Get-Content -LiteralPath $ChecksumPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    if ($lines.Count -eq 0) {
        throw 'The source package checksum file is empty.'
    }

    foreach ($line in $lines) {
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') {
            throw "Invalid checksum line: $line"
        }
        $expected = $Matches[1].ToLowerInvariant()
        $relativePath = $Matches[2]
        if ([IO.Path]::IsPathRooted($relativePath)) {
            throw "Checksum entry must be relative: $relativePath"
        }
        $candidate = [IO.Path]::GetFullPath((Join-Path $Root $relativePath))
        if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Checksum entry escapes the package directory: $relativePath"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Checksummed package member is missing: $relativePath"
        }
        $actual = Get-Sha256 -Path $candidate
        if ($actual -ne $expected) {
            throw "Checksum mismatch for source package member: $relativePath"
        }
    }
}

function Get-OrCreateRelease {
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$TargetCommit
    )

    $encodedTag = [Uri]::EscapeDataString($Tag)
    $lookupUri = "$script:ApiBase/repos/$script:Repository/releases/tags/$encodedTag"
    try {
        $release = Invoke-GitHubJson -Method Get -Uri $lookupUri -Body $null
    } catch {
        if ((Get-HttpStatusCode -ErrorRecord $_) -ne 404) {
            throw
        }
        $createUri = "$script:ApiBase/repos/$script:Repository/releases"
        $payload = [ordered]@{
            tag_name = $Tag
            target_commitish = $TargetCommit
            name = $Name
            body = $Description
            draft = $false
            prerelease = $true
            generate_release_notes = $false
        }
        try {
            $release = Invoke-GitHubJson -Method Post -Uri $createUri -Body $payload
        } catch {
            # Windows and Android may reach release creation at the same time.
            # A 422 is safe to recover only by resolving the exact same tag.
            if ((Get-HttpStatusCode -ErrorRecord $_) -ne 422) {
                throw
            }
            $release = $null
            foreach ($attempt in 1..5) {
                try {
                    $release = Invoke-GitHubJson -Method Get -Uri $lookupUri -Body $null
                    break
                } catch {
                    if ((Get-HttpStatusCode -ErrorRecord $_) -ne 404 -or $attempt -eq 5) {
                        throw
                    }
                    Start-Sleep -Seconds 2
                }
            }
        }
    }

    if ($release.tag_name -ne $Tag -or [bool]$release.draft) {
        throw "Resolved release does not match required published tag $Tag."
    }

    $tagRef = $null
    foreach ($attempt in 1..5) {
        try {
            $tagRef = Invoke-GitHubJson `
                -Method Get `
                -Uri "$script:ApiBase/repos/$script:Repository/git/ref/tags/$encodedTag" `
                -Body $null
            break
        } catch {
            if ((Get-HttpStatusCode -ErrorRecord $_) -ne 404 -or $attempt -eq 5) {
                throw
            }
            Start-Sleep -Seconds 2
        }
    }
    if ($tagRef.object.type -ne 'commit' -or
        $tagRef.object.sha -ne $TargetCommit) {
        throw "Release tag $Tag does not point to packaged source commit $TargetCommit."
    }
    return $release
}

function Save-ReleaseAssetDownload {
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$Destination
    )

    $downloadHeaders = @{
        Accept = 'application/octet-stream'
        Authorization = "Bearer $script:Token"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Neura-CI-Release-Publisher'
    }
    Invoke-WebRequest `
        -UseBasicParsing `
        -Method Get `
        -Uri $Asset.url `
        -Headers $downloadHeaders `
        -MaximumRedirection 10 `
        -OutFile $Destination | Out-Null
}

function Publish-ReleaseAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$VerificationRoot
    )

    $localFile = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($localFile.Length -le 0) {
        throw "Release asset is empty: $Path"
    }
    if ($localFile.Length -ge 2GB) {
        throw "Release asset exceeds GitHub's per-file 2 GiB limit: $Name"
    }

    $expectedHash = Get-Sha256 -Path $localFile.FullName
    $existingAssets = Invoke-GitHubJson `
        -Method Get `
        -Uri "$script:ApiBase/repos/$script:Repository/releases/$($Release.id)/assets?per_page=100" `
        -Body $null
    $asset = Find-GitHubReleaseAsset -Assets $existingAssets -Name $Name
    if ($null -eq $asset) {
        $uploadBase = $Release.upload_url -replace '\{\?name,label\}$', ''
        $uploadUri = "${uploadBase}?name=$([Uri]::EscapeDataString($Name))"
        $asset = Invoke-RestMethod `
            -Method Post `
            -Uri $uploadUri `
            -Headers $script:GitHubHeaders `
            -ContentType (Get-ContentType -Path $localFile.FullName) `
            -InFile $localFile.FullName `
            -ErrorAction Stop
    }

    if ($asset.state -ne 'uploaded' -or [int64]$asset.size -ne $localFile.Length) {
        throw "GitHub did not confirm a complete upload for $Name."
    }

    $downloadPath = Join-Path $VerificationRoot $Name
    Save-ReleaseAssetDownload -Asset $asset -Destination $downloadPath
    $downloaded = Get-Item -LiteralPath $downloadPath -ErrorAction Stop
    if ($downloaded.Length -ne $localFile.Length) {
        throw "Downloaded asset length does not match the uploaded file: $Name"
    }
    $downloadHash = Get-Sha256 -Path $downloaded.FullName
    if ($downloadHash -ne $expectedHash) {
        throw "Downloaded asset checksum does not match the uploaded file: $Name"
    }

    return [pscustomobject]@{
        Name = $Name
        Size = $localFile.Length
        Sha256 = $expectedHash
        DownloadUrl = $asset.browser_download_url
    }
}

$script:Token = Get-RequiredEnvironmentValue -Name 'GITHUB_TOKEN'
$script:Repository = Get-RequiredEnvironmentValue -Name 'GITHUB_REPOSITORY'
$script:ApiBase = (Get-RequiredEnvironmentValue -Name 'GITHUB_API_URL').TrimEnd('/')
$script:GitHubHeaders = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $script:Token"
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'Neura-CI-Release-Publisher'
}
$serverUrl = (Get-RequiredEnvironmentValue -Name 'GITHUB_SERVER_URL').TrimEnd('/')
$runId = Get-RequiredEnvironmentValue -Name 'GITHUB_RUN_ID'
$runAttempt = Get-RequiredEnvironmentValue -Name 'GITHUB_RUN_ATTEMPT'
$sourceCommit = (Get-RequiredEnvironmentValue -Name 'GITHUB_SHA').ToLowerInvariant()
$headCommit = (Get-RequiredEnvironmentValue -Name 'NEURA_RELEASE_HEAD_SHA').ToLowerInvariant()

foreach ($commit in @($sourceCommit, $headCommit)) {
    if ($commit -notmatch '^[0-9a-f]{40}$') {
        throw "Invalid GitHub commit identity: $commit"
    }
}
if ($runId -notmatch '^\d+$' -or $runAttempt -notmatch '^\d+$') {
    throw 'GitHub run identity must be numeric.'
}
if (-not (Test-Path -LiteralPath $PackagePath -PathType Container)) {
    throw "Package directory does not exist: $PackagePath"
}
if (-not (Test-Path -LiteralPath $BuildVolume -PathType Container)) {
    throw "Build volume does not exist: $BuildVolume"
}

$checksumPath = Join-Path $PackagePath 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
    throw 'The package is missing SHA256SUMS.txt.'
}
Assert-SourceChecksums -Root $PackagePath -ChecksumPath $checksumPath

$extension = if ($Platform -eq 'windows') { '.zip' } else { '.apk' }
$binaryFiles = @(Get-ChildItem -LiteralPath $PackagePath -Filter "*$extension" -File)
if ($binaryFiles.Count -ne 1 -or $binaryFiles[0].Length -le 0) {
    throw "Expected exactly one non-empty $extension package file."
}

$sourceManifestPath = Join-Path $PackagePath 'build-manifest.json'
$sourceManifest = $null
if (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf) {
    $sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json
    if ($sourceManifest.source_commit -ne $sourceCommit -or
        $sourceManifest.platform -ne $Platform -or
        [string]$sourceManifest.run_id -ne $runId -or
        [string]$sourceManifest.run_attempt -ne $runAttempt) {
        throw 'The preserved package manifest does not match this workflow run.'
    }
}

$pullRequestNumber = [Environment]::GetEnvironmentVariable('NEURA_RELEASE_PR_NUMBER')
if (-not [string]::IsNullOrWhiteSpace($pullRequestNumber) -and
    $pullRequestNumber -notmatch '^\d+$') {
    throw 'NEURA_RELEASE_PR_NUMBER must be empty or numeric.'
}

$sourceShort = $sourceCommit.Substring(0, 12)
$headShort = $headCommit.Substring(0, 12)
if ([string]::IsNullOrWhiteSpace($pullRequestNumber)) {
    $refName = Get-RequiredEnvironmentValue -Name 'GITHUB_REF_NAME'
    $safeRef = ($refName.ToLowerInvariant() -replace '[^a-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeRef)) {
        throw 'The workflow ref cannot form a safe release tag.'
    }
    $tag = "neura-ci-$safeRef-$headShort-$sourceShort"
    $releaseName = "Neura CI $refName at $headShort"
    $releaseContext = "Branch/ref: $refName"
} else {
    $tag = "neura-ci-pr-$pullRequestNumber-$headShort-$sourceShort"
    $releaseName = "Neura CI PR #$pullRequestNumber at $headShort"
    $releaseContext = "Pull request: #$pullRequestNumber"
}

$runUrl = "$serverUrl/$script:Repository/actions/runs/$runId"
$description = @"
Automated mandatory Neura package delivery.

$releaseContext
PR head commit: $headCommit
Packaged source commit: $sourceCommit
Workflow run: $runUrl
Device QA: pending
"@

$release = Get-OrCreateRelease `
    -Tag $tag `
    -Name $releaseName `
    -Description $description `
    -TargetCommit $sourceCommit

$runKey = "$runId-$runAttempt"
$platformLabel = if ($Platform -eq 'windows') { 'Windows' } else { 'Android' }
$stagingRoot = Join-Path $BuildVolume "neura-release-staging\$runKey\$Platform"
$verificationRoot = Join-Path $BuildVolume "neura-release-verification\$runKey\$Platform"
if (Test-Path -LiteralPath $stagingRoot) {
    throw "Release staging path already exists; refusing to overwrite it: $stagingRoot"
}
if (Test-Path -LiteralPath $verificationRoot) {
    throw "Release verification path already exists; refusing to overwrite it: $verificationRoot"
}

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
New-Item -ItemType Directory -Path $verificationRoot -Force | Out-Null
try {
    $binaryName = "NeuraCompanion-$platformLabel-$headShort-$runKey$extension"
    # The API accepts the release name separately from the local path. Upload
    # the preserved package directly instead of allocating a second large copy.
    $binaryPath = $binaryFiles[0].FullName

    $projectUrl = [Environment]::GetEnvironmentVariable('NEURA_CLIENT_PROJECT_URL')
    $configSha256 = [Environment]::GetEnvironmentVariable('NEURA_CLIENT_CONFIG_SHA256')
    $configuration = if (
        -not [string]::IsNullOrWhiteSpace($projectUrl) -and
        -not [string]::IsNullOrWhiteSpace($configSha256)
    ) { 'configured' } else { 'local-only' }

    if ($null -ne $sourceManifest) {
        $projectUrl = [string]$sourceManifest.project_url
        $configSha256 = [string]$sourceManifest.config_sha256
        $configuration = 'configured'
    }

    $manifest = [ordered]@{
        source_commit = $sourceCommit
        head_commit = $headCommit
        platform = $Platform
        configuration = $configuration
        project_url = $projectUrl
        config_sha256 = $configSha256
        run_id = $runId
        run_attempt = $runAttempt
        release_tag = $tag
        delivery = 'github-release'
        download_verification = 'required'
        device_qa = 'pending'
    }
    $manifestName = "NeuraCompanion-$platformLabel-$headShort-$runKey-build-manifest.json"
    $manifestPath = Join-Path $stagingRoot $manifestName
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $checksumsName = "NeuraCompanion-$platformLabel-$headShort-$runKey-SHA256SUMS.txt"
    $stagedChecksumsPath = Join-Path $stagingRoot $checksumsName
    @(
        "$(Get-Sha256 -Path $binaryPath)  $binaryName",
        "$(Get-Sha256 -Path $manifestPath)  $manifestName"
    ) | Set-Content -LiteralPath $stagedChecksumsPath -Encoding ASCII

    $published = @(
        Publish-ReleaseAsset -Release $release -Path $binaryPath -Name $binaryName -VerificationRoot $verificationRoot
        Publish-ReleaseAsset -Release $release -Path $manifestPath -Name $manifestName -VerificationRoot $verificationRoot
        Publish-ReleaseAsset -Release $release -Path $stagedChecksumsPath -Name $checksumsName -VerificationRoot $verificationRoot
    )

    $summary = @(
        "### Mandatory $platformLabel package delivery",
        '',
        "Release: [$tag]($($release.html_url))",
        "PR head: ``$headCommit``",
        "Packaged source: ``$sourceCommit``",
        '',
        '| Download-verified asset | Bytes | SHA-256 |',
        '| --- | ---: | --- |'
    )
    foreach ($asset in $published) {
        $summary += "| [$($asset.Name)]($($asset.DownloadUrl)) | $($asset.Size) | ``$($asset.Sha256)`` |"
    }
    $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append

    @(
        "release_url=$($release.html_url)",
        "release_tag=$tag"
    ) | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append

    Write-Host "Published and download-verified $($published.Count) required $Platform release assets."
    Write-Host "Release: $($release.html_url)"
} finally {
    foreach ($path in @($verificationRoot, $stagingRoot)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
