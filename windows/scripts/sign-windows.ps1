[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$DigestAlgorithm = "sha256",
    [string]$SignToolPath = "signtool.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FilePath)) {
    throw "The target file was not found: $FilePath"
}

if (-not $env:BUGNARRATOR_CERT_PATH) {
    throw "Set BUGNARRATOR_CERT_PATH to the code-signing certificate path before signing."
}

if (-not (Test-Path $env:BUGNARRATOR_CERT_PATH)) {
    throw "The code-signing certificate was not found at $env:BUGNARRATOR_CERT_PATH"
}

if (-not $env:BUGNARRATOR_CERT_PASSWORD) {
    throw "Set BUGNARRATOR_CERT_PASSWORD before signing."
}

& $SignToolPath sign `
    /fd $DigestAlgorithm `
    /td $DigestAlgorithm `
    /tr $TimestampUrl `
    /f $env:BUGNARRATOR_CERT_PATH `
    /p $env:BUGNARRATOR_CERT_PASSWORD `
    $FilePath

if ($LASTEXITCODE -ne 0) {
    throw "signtool failed."
}
