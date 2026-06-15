[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string]$Endpoint = "https://wus3.codesigning.azure.net/",
    [string]$Account = "bugnarrator-signing",
    [string]$CertificateProfile = "bugnarrator-public",
    [string]$TimestampUrl = "http://timestamp.acs.microsoft.com",
    [string]$DigestAlgorithm = "SHA256",
    [string]$SignToolPath = "",
    [string]$DlibPath = "",
    [string]$DlibVersion = "1.0.60"
)

# Signs a file with Azure Trusted Signing using signtool plus the Azure.CodeSigning dlib.
# Authentication uses Azure.Identity DefaultAzureCredential, so an `az login` session (or the
# AZURE_TENANT_ID/AZURE_CLIENT_ID/AZURE_CLIENT_SECRET service-principal env vars in CI) is required.
# The signing identity needs the "Trusted Signing Certificate Profile Signer" data-plane role on the
# account, and the certificate profile must already exist (a PublicTrust profile requires a completed
# identity validation).

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

if (-not (Test-Path $FilePath)) {
    throw "The target file was not found: $FilePath"
}

function Resolve-SignTool {
    param([string]$Explicit)

    # An explicit value wins when it resolves; otherwise fall back to PATH and then the newest
    # Windows SDK build, so the common default of "signtool.exe" still works when it is not on PATH.
    if ($Explicit) {
        if (Test-Path $Explicit) {
            return (Resolve-Path $Explicit).Path
        }
        $command = Get-Command $Explicit -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
        throw "signtool.exe was not found at the specified path: $Explicit"
    }

    $command = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $sdkBinDir = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path $sdkBinDir) {
        $candidate = Get-ChildItem -Path $sdkBinDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "x64\signtool.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1

        if ($candidate) {
            return $candidate
        }
    }

    throw "signtool.exe was not found. Install the Windows SDK or pass -SignToolPath."
}

function Resolve-Dlib {
    param([string]$Explicit, [string]$Version)

    if ($Explicit) {
        if (Test-Path $Explicit) {
            return (Resolve-Path $Explicit).Path
        }

        throw "Trusted Signing dlib was not found at $Explicit"
    }

    if ($env:BUGNARRATOR_SIGNING_DLIB -and (Test-Path $env:BUGNARRATOR_SIGNING_DLIB)) {
        return (Resolve-Path $env:BUGNARRATOR_SIGNING_DLIB).Path
    }

    $globalPackages = $null
    if ($env:NUGET_PACKAGES -and (Test-Path $env:NUGET_PACKAGES)) {
        $globalPackages = (Resolve-Path $env:NUGET_PACKAGES).Path
    }

    if (-not $globalPackages) {
        $localsLine = (& dotnet nuget locals global-packages --list) 2>$null | Select-Object -First 1
        if ($localsLine -match 'global-packages:\s*(.+)$') {
            $globalPackages = $Matches[1].Trim()
        }
    }

    if (-not $globalPackages) {
        $globalPackages = Join-Path $env:USERPROFILE ".nuget\packages"
    }

    $dllPath = Join-Path $globalPackages "microsoft.trusted.signing.client\$Version\bin\x64\Azure.CodeSigning.Dlib.dll"
    if (Test-Path $dllPath) {
        return $dllPath
    }

    Write-Host "Restoring Microsoft.Trusted.Signing.Client $Version from NuGet..."
    $restoreDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bn-ts-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $restoreDir | Out-Null
    try {
        $projectPath = Join-Path $restoreDir "restore.csproj"
        @(
            '<Project Sdk="Microsoft.NET.Sdk">',
            '  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>',
            '  <ItemGroup>',
            "    <PackageReference Include=""Microsoft.Trusted.Signing.Client"" Version=""$Version"" />",
            '  </ItemGroup>',
            '</Project>'
        ) | Set-Content -Path $projectPath -Encoding utf8

        & dotnet restore $projectPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet restore for Microsoft.Trusted.Signing.Client $Version failed."
        }
    }
    finally {
        Remove-Item $restoreDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $dllPath) {
        return $dllPath
    }

    throw "Could not locate Azure.CodeSigning.Dlib.dll for version $Version after restore. Pass -DlibPath."
}

$signTool = Resolve-SignTool -Explicit $SignToolPath
$dlib = Resolve-Dlib -Explicit $DlibPath -Version $DlibVersion

$metadataPath = $null
try {
    # Trusted Signing metadata consumed by the dlib (no secrets; safe to write to a temp file).
    $metadata = [ordered]@{
        Endpoint               = $Endpoint
        CodeSigningAccountName = $Account
        CertificateProfileName = $CertificateProfile
    }
    $metadataPath = Join-Path ([System.IO.Path]::GetTempPath()) ("bugnarrator-signing-" + [System.Guid]::NewGuid().ToString("N") + ".json")
    $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding utf8

    & $signTool sign `
        /v `
        /fd $DigestAlgorithm `
        /tr $TimestampUrl `
        /td $DigestAlgorithm `
        /dlib $dlib `
        /dmdf $metadataPath `
        $FilePath

    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed with exit code $LASTEXITCODE."
    }
}
finally {
    if ($metadataPath -and (Test-Path $metadataPath)) {
        Remove-Item $metadataPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Signed $FilePath with Azure Trusted Signing ($Account / $CertificateProfile)."
