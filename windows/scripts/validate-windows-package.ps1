[CmdletBinding()]
param(
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$publishDirectory = Join-Path $repoRoot "$OutputRoot\publish\$Runtime"
$packagePath = Join-Path $repoRoot "$OutputRoot\packages\BugNarrator-windows-$Runtime.zip"
$validationDirectory = Join-Path $repoRoot "$OutputRoot\validation"
$validationReportPath = Join-Path $validationDirectory "BugNarrator-windows-$Runtime-validation.json"
$requiredPublishFiles = @(
    "BugNarrator.Windows.exe",
    "BugNarrator.Windows.dll",
    "BugNarrator.Windows.deps.json",
    "BugNarrator.Windows.runtimeconfig.json"
)

function Get-RelativeArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.Path]::GetRelativePath($repoRoot, $Path).Replace('\', '/')
}

function Get-ZipEntrySha256 {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = $Entry.Open()
        try {
            return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "")
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha256.Dispose()
    }
}

if (-not (Test-Path $publishDirectory)) {
    throw "Publish directory was not found: $publishDirectory"
}

if (-not (Test-Path $packagePath)) {
    throw "Package was not found: $packagePath"
}

New-Item -ItemType Directory -Force -Path $validationDirectory | Out-Null

if (Test-Path $validationReportPath) {
    Remove-Item $validationReportPath -Force
}

foreach ($requiredFile in $requiredPublishFiles) {
    $publishPath = Join-Path $publishDirectory $requiredFile
    if (-not (Test-Path $publishPath)) {
        throw "Required publish artifact missing: $publishPath"
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
$validatedFiles = @()

try {
    foreach ($requiredFile in $requiredPublishFiles) {
        $entry = $archive.Entries | Where-Object { $_.FullName -eq $requiredFile }
        if (-not $entry) {
            throw "Required packaged artifact missing: $requiredFile"
        }

        $publishPath = Join-Path $publishDirectory $requiredFile
        $publishSha256 = (Get-FileHash -Path $publishPath -Algorithm SHA256).Hash
        $packageEntrySha256 = Get-ZipEntrySha256 -Entry $entry

        if ($publishSha256 -ne $packageEntrySha256) {
            throw "Packaged artifact hash mismatch for $requiredFile."
        }

        $validatedFiles += [PSCustomObject]@{
            path = $requiredFile
            publishSha256 = $publishSha256
            packageEntrySha256 = $packageEntrySha256
            compressedLength = $entry.CompressedLength
            uncompressedLength = $entry.Length
        }
    }
}
finally {
    $archive.Dispose()
}

$smokeExecutable = Join-Path $publishDirectory "BugNarrator.Windows.exe"
$smokeOutputPath = Join-Path $publishDirectory "bugnarrator-smoke-report.json"

if (Test-Path $smokeOutputPath) {
    Remove-Item $smokeOutputPath -Force
}

$smokeProcess = Start-Process `
    -FilePath $smokeExecutable `
    -ArgumentList @("--smoke-output", $smokeOutputPath) `
    -WorkingDirectory $publishDirectory `
    -WindowStyle Hidden `
    -PassThru `
    -Wait

if ($smokeProcess.ExitCode -ne 0) {
    throw "Packaged smoke executable exited with code $($smokeProcess.ExitCode)."
}

if (-not (Test-Path $smokeOutputPath)) {
    throw "Smoke probe output was not created: $smokeOutputPath"
}

$smokeReport = Get-Content $smokeOutputPath -Raw | ConvertFrom-Json
if ($smokeReport.mode -ne "smoke") {
    throw "Unexpected smoke report mode: $($smokeReport.mode)"
}

if ($smokeReport.appName -ne "BugNarrator.Windows") {
    throw "Unexpected smoke report appName: $($smokeReport.appName)"
}

if (-not $smokeReport.version) {
    throw "Smoke report did not include a version."
}

if (-not $smokeReport.windowsVersion) {
    throw "Smoke report did not include a Windows version."
}

if (-not $smokeReport.dotNetVersion) {
    throw "Smoke report did not include a .NET version."
}

if (-not $smokeReport.generatedAt) {
    throw "Smoke report did not include a generatedAt timestamp."
}

$validationReport = [PSCustomObject]@{
    runtime = $Runtime
    validatedAt = (Get-Date).ToUniversalTime().ToString("o")
    packagePath = Get-RelativeArtifactPath -Path $packagePath
    packageSha256 = (Get-FileHash -Path $packagePath -Algorithm SHA256).Hash
    publishDirectory = Get-RelativeArtifactPath -Path $publishDirectory
    validationReportPath = Get-RelativeArtifactPath -Path $validationReportPath
    smokeReportPath = Get-RelativeArtifactPath -Path $smokeOutputPath
    requiredFiles = $validatedFiles
    smokeReport = [PSCustomObject]@{
        mode = $smokeReport.mode
        appName = $smokeReport.appName
        version = $smokeReport.version
        windowsVersion = $smokeReport.windowsVersion
        dotNetVersion = $smokeReport.dotNetVersion
        generatedAt = $smokeReport.generatedAt
    }
}

$validationReport |
    ConvertTo-Json -Depth 6 |
    Set-Content -Path $validationReportPath

Write-Host "Windows package validation passed for $packagePath"
Write-Host "Validation report written to $validationReportPath"
