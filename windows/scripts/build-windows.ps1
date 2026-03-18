[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

Push-Location $repoRoot
try {
    dotnet restore "windows/BugNarrator.Windows.sln"
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed."
    }

    dotnet build "windows/BugNarrator.Windows.sln" -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed."
    }
}
finally {
    Pop-Location
}
