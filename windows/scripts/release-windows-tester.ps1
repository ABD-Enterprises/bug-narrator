[CmdletBinding()]
param(
    [ValidateSet("Release")]
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts",
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$DigestAlgorithm = "sha256",
    [string]$SignToolPath = "signtool.exe",
    [string]$ReleaseNotesPath = "",
    [switch]$UseTrustedSigning,
    [string]$TrustedSigningEndpoint = "https://wus3.codesigning.azure.net/",
    [string]$TrustedSigningAccount = "bugnarrator-signing",
    [string]$TrustedSigningCertificateProfile = "bugnarrator-public",
    [string]$TrustedSigningTimestampUrl = "http://timestamp.acs.microsoft.com"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$publishDirectory = Join-Path $repoRoot "$OutputRoot\publish\$Runtime"
$packageDirectory = Join-Path $repoRoot "$OutputRoot\packages"
$validationDirectory = Join-Path $repoRoot "$OutputRoot\validation"
$packagePath = Join-Path $packageDirectory "BugNarrator-windows-$Runtime.zip"
$executablePath = Join-Path $publishDirectory "BugNarrator.Windows.exe"
$signatureReportPath = Join-Path $validationDirectory "BugNarrator-windows-$Runtime-signature.json"
$validationReportPath = Join-Path $validationDirectory "BugNarrator-windows-$Runtime-validation.json"

function Get-RelativeArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootPath = [System.IO.Path]::GetFullPath($repoRoot)
    if (-not $rootPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootPath = "$rootPath$([System.IO.Path]::DirectorySeparatorChar)"
    }

    $rootUri = [System.Uri]::new($rootPath)
    $pathUri = [System.Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

if (-not $UseTrustedSigning) {
    if (-not $env:BUGNARRATOR_CERT_PATH) {
        throw "Set BUGNARRATOR_CERT_PATH to an external Windows code-signing certificate before producing a signed tester release, or pass -UseTrustedSigning to sign with Azure Trusted Signing."
    }

    if (-not $env:BUGNARRATOR_CERT_PASSWORD) {
        throw "Set BUGNARRATOR_CERT_PASSWORD before producing a signed tester release, or pass -UseTrustedSigning to sign with Azure Trusted Signing."
    }
}

Push-Location $repoRoot
try {
    & "$PSScriptRoot\package-windows.ps1" -Configuration $Configuration -Runtime $Runtime -OutputRoot $OutputRoot
    if ($LASTEXITCODE -ne 0) {
        throw "package-windows.ps1 failed."
    }

    if ($UseTrustedSigning) {
        & "$PSScriptRoot\sign-windows-trustedsigning.ps1" `
            -FilePath $executablePath `
            -Endpoint $TrustedSigningEndpoint `
            -Account $TrustedSigningAccount `
            -CertificateProfile $TrustedSigningCertificateProfile `
            -TimestampUrl $TrustedSigningTimestampUrl `
            -DigestAlgorithm $DigestAlgorithm `
            -SignToolPath $SignToolPath
        if ($LASTEXITCODE -ne 0) {
            throw "sign-windows-trustedsigning.ps1 failed."
        }
    }
    else {
        & "$PSScriptRoot\sign-windows.ps1" `
            -FilePath $executablePath `
            -TimestampUrl $TimestampUrl `
            -DigestAlgorithm $DigestAlgorithm `
            -SignToolPath $SignToolPath
        if ($LASTEXITCODE -ne 0) {
            throw "sign-windows.ps1 failed."
        }
    }

    & "$PSScriptRoot\verify-windows-signature.ps1" `
        -FilePath $executablePath `
        -ReportPath $signatureReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "verify-windows-signature.ps1 failed."
    }

    if (Test-Path $packagePath) {
        Remove-Item $packagePath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $publishDirectory,
        $packagePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false)

    & "$PSScriptRoot\validate-windows-package.ps1" -Runtime $Runtime -OutputRoot $OutputRoot
    if ($LASTEXITCODE -ne 0) {
        throw "validate-windows-package.ps1 failed."
    }

    if (-not $ReleaseNotesPath) {
        $ReleaseNotesPath = Join-Path $validationDirectory "BugNarrator-windows-$Runtime-release-notes.md"
    }
    $releaseNotesDirectory = Split-Path -Parent $ReleaseNotesPath
    if ($releaseNotesDirectory) {
        New-Item -ItemType Directory -Force -Path $releaseNotesDirectory | Out-Null
    }

    $packageHash = (Get-FileHash -Path $packagePath -Algorithm SHA256).Hash
    $signatureReport = Get-Content $signatureReportPath -Raw | ConvertFrom-Json
    $signerSubject = $signatureReport.signerCertificate.subject
    $signerThumbprint = $signatureReport.signerCertificate.thumbprint

    @(
        "# BugNarrator Windows tester release",
        "",
        "- Artifact: ``$(Get-RelativeArtifactPath -Path $packagePath)``",
        "- SHA-256: ``$packageHash``",
        "- Runtime: ``$Runtime``",
        "- Configuration: ``$Configuration``",
        "- Signed executable: ``$(Get-RelativeArtifactPath -Path $executablePath)``",
        "- Authenticode signer: ``$signerSubject``",
        "- Authenticode thumbprint: ``$signerThumbprint``",
        "- Signature evidence: ``$(Get-RelativeArtifactPath -Path $signatureReportPath)``",
        "- Package validation evidence: ``$(Get-RelativeArtifactPath -Path $validationReportPath)``",
        "",
        "Clean-machine validation is still required before broad tester distribution. Run the Windows validation checklist on a fresh Windows machine or VM and attach the resulting notes to the GitHub Release."
    ) | Set-Content -Path $ReleaseNotesPath

    Write-Host "Signed Windows tester package created at $packagePath"
    Write-Host "Release notes written to $ReleaseNotesPath"
}
finally {
    Pop-Location
}
