[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

Push-Location $repoRoot
try {
    dotnet test "windows/BugNarrator.Windows.sln" -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet test failed."
    }
}
finally {
    Pop-Location
}
