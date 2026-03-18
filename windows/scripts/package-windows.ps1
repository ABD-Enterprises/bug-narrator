[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$publishDirectory = Join-Path $repoRoot "$OutputRoot\publish\$Runtime"
$packageDirectory = Join-Path $repoRoot "$OutputRoot\packages"
$packagePath = Join-Path $packageDirectory "BugNarrator-windows-$Runtime.zip"

Push-Location $repoRoot
try {
    if (Test-Path $publishDirectory) {
        Remove-Item $publishDirectory -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $publishDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null

    dotnet publish "windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj" `
        -c $Configuration `
        -r $Runtime `
        --self-contained false `
        -o $publishDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed."
    }

    if (Test-Path $packagePath) {
        Remove-Item $packagePath -Force
    }

    Compress-Archive -Path (Join-Path $publishDirectory "*") -DestinationPath $packagePath
    Write-Host "Package created at $packagePath"
}
finally {
    Pop-Location
}
