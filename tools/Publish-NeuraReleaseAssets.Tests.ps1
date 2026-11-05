#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$publisher = Join-Path $PSScriptRoot 'Publish-NeuraReleaseAssets.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($publisher, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Publisher syntax errors: $parseErrors" }
# Import only pure checksum helpers; tests must never publish a release.
foreach ($definition in $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Get-Sha256', 'Assert-SourceChecksums')
}, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}

function Assert-RejectedChecksum {
    param([string]$Entry, [string]$Pattern)
    [IO.File]::WriteAllText($checksum, "$hash  $Entry`n")
    $rejected = $false
    try { Assert-SourceChecksums -Root $package -ChecksumPath $checksum }
    catch {
        $rejected = $true
        if ($_.Exception.Message -notlike $Pattern) { throw }
    }
    if (-not $rejected) { throw "Unsafe checksum entry was accepted: $Entry" }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('neura-release-checksums-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $fixture 'package'
$checksum = Join-Path $package 'SHA256SUMS.txt'
try {
    New-Item -ItemType Directory -Path (Join-Path $package 'nested') -Force | Out-Null
    $apk = Join-Path $package 'NeuraCompanion-Android-debug.apk'
    [IO.File]::WriteAllText($apk, 'synthetic APK fixture')
    $hash = Get-Sha256 -Path $apk
    Copy-Item -LiteralPath $apk -Destination (Join-Path $package 'nested/member.apk')
    foreach ($entry in @('NeuraCompanion-Android-debug.apk', 'nested/member.apk', 'nested/../NeuraCompanion-Android-debug.apk')) {
        [IO.File]::WriteAllText($checksum, "$hash  $entry`n")
        Assert-SourceChecksums -Root $package -ChecksumPath $checksum
        Assert-SourceChecksums -Root ($package + [IO.Path]::DirectorySeparatorChar) -ChecksumPath $checksum
    }
    Write-Host 'PASS: flat, nested, normalized and trailing-separator package paths.'

    $outside = Join-Path $fixture 'outside.apk'
    Copy-Item -LiteralPath $apk -Destination $outside
    $sibling = Join-Path $fixture 'package-sibling'
    New-Item -ItemType Directory -Path $sibling | Out-Null
    Copy-Item -LiteralPath $apk -Destination (Join-Path $sibling 'outside.apk')
    Assert-RejectedChecksum -Entry '../outside.apk' -Pattern 'Checksum entry escapes*'
    Assert-RejectedChecksum -Entry '../package-sibling/outside.apk' -Pattern 'Checksum entry escapes*'
    Assert-RejectedChecksum -Entry $outside -Pattern 'Checksum entry must be relative*'
    Assert-RejectedChecksum -Entry 'missing.apk' -Pattern 'Checksummed package member is missing*'
    if ([IO.Path]::DirectorySeparatorChar -eq '/') {
        $caseSibling = Join-Path $fixture 'Package'
        New-Item -ItemType Directory -Path $caseSibling | Out-Null
        Copy-Item -LiteralPath $apk -Destination (Join-Path $caseSibling 'outside.apk')
        Assert-RejectedChecksum -Entry '../Package/outside.apk' -Pattern 'Checksum entry escapes*'
    }
    Write-Host 'PASS: parent traversal, prefix siblings, absolute paths and missing members are rejected.'

    [IO.File]::WriteAllText($apk, 'tampered fixture')
    Assert-RejectedChecksum -Entry 'NeuraCompanion-Android-debug.apk' -Pattern 'Checksum mismatch*'
    foreach ($text in @('', 'not a checksum')) {
        [IO.File]::WriteAllText($checksum, $text)
        $rejected = $false
        try { Assert-SourceChecksums -Root $package -ChecksumPath $checksum }
        catch { $rejected = $true }
        if (-not $rejected) { throw 'Empty or malformed checksums were accepted.' }
    }
    Write-Host 'PASS: tampered bytes and empty/malformed checksum lists are rejected.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
