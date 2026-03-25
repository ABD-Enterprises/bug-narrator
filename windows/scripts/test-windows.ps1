[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$solutionPath = "windows/BugNarrator.Windows.sln"
$testProjects = @(
    "windows/tests/BugNarrator.Core.Tests/BugNarrator.Core.Tests.csproj",
    "windows/tests/BugNarrator.Windows.Tests/BugNarrator.Windows.Tests.csproj"
)

Push-Location $repoRoot
try {
    if (-not $NoBuild) {
        dotnet build $solutionPath -c $Configuration
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet build failed."
        }
    }

    foreach ($testProject in $testProjects) {
        dotnet test $testProject -c $Configuration --no-build
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet test failed for $testProject."
        }
    }
}
finally {
    Pop-Location
}
