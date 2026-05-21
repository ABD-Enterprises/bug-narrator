[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FilePath)) {
    throw "The signed file was not found: $FilePath"
}

$signature = Get-AuthenticodeSignature -FilePath $FilePath
if ($signature.Status -ne "Valid") {
    throw "Authenticode signature is not valid for $FilePath. Status: $($signature.Status). Message: $($signature.StatusMessage)"
}

$report = [PSCustomObject]@{
    filePath = (Resolve-Path $FilePath).Path
    status = [string]$signature.Status
    statusMessage = $signature.StatusMessage
    signerCertificate = if ($signature.SignerCertificate) {
        [PSCustomObject]@{
            subject = $signature.SignerCertificate.Subject
            issuer = $signature.SignerCertificate.Issuer
            thumbprint = $signature.SignerCertificate.Thumbprint
            notBefore = $signature.SignerCertificate.NotBefore.ToUniversalTime().ToString("o")
            notAfter = $signature.SignerCertificate.NotAfter.ToUniversalTime().ToString("o")
        }
    } else {
        $null
    }
    timeStamperCertificate = if ($signature.TimeStamperCertificate) {
        [PSCustomObject]@{
            subject = $signature.TimeStamperCertificate.Subject
            issuer = $signature.TimeStamperCertificate.Issuer
            thumbprint = $signature.TimeStamperCertificate.Thumbprint
            notBefore = $signature.TimeStamperCertificate.NotBefore.ToUniversalTime().ToString("o")
            notAfter = $signature.TimeStamperCertificate.NotAfter.ToUniversalTime().ToString("o")
        }
    } else {
        $null
    }
    verifiedAt = (Get-Date).ToUniversalTime().ToString("o")
}

if ($ReportPath) {
    $reportDirectory = Split-Path -Parent $ReportPath
    if ($reportDirectory) {
        New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportPath
}

Write-Host "Authenticode signature is valid for $FilePath"
if ($signature.SignerCertificate) {
    Write-Host "Signer: $($signature.SignerCertificate.Subject)"
    Write-Host "Thumbprint: $($signature.SignerCertificate.Thumbprint)"
}
