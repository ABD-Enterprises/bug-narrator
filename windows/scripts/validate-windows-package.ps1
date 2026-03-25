[CmdletBinding()]
param(
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$publishDirectory = Join-Path $repoRoot "$OutputRoot\publish\$Runtime"
$packagePath = Join-Path $repoRoot "$OutputRoot\packages\BugNarrator-windows-$Runtime.zip"
$requiredPublishFiles = @(
    "BugNarrator.Windows.exe",
    "BugNarrator.Windows.dll",
    "BugNarrator.Windows.deps.json",
    "BugNarrator.Windows.runtimeconfig.json"
)

if (-not (Test-Path $publishDirectory)) {
    throw "Publish directory was not found: $publishDirectory"
}

if (-not (Test-Path $packagePath)) {
    throw "Package was not found: $packagePath"
}

foreach ($requiredFile in $requiredPublishFiles) {
    $publishPath = Join-Path $publishDirectory $requiredFile
    if (-not (Test-Path $publishPath)) {
        throw "Required publish artifact missing: $publishPath"
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)

try {
    foreach ($requiredFile in $requiredPublishFiles) {
        $entry = $archive.Entries | Where-Object { $_.FullName -eq $requiredFile }
        if (-not $entry) {
            throw "Required packaged artifact missing: $requiredFile"
        }
    }
}
finally {
    $archive.Dispose()
}

Write-Host "Windows package validation passed for $packagePath"
