[CmdletBinding()]
param(
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts",
    [int]$StartupDelaySeconds = 6
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$publishDirectory = Join-Path $repoRoot "$OutputRoot\publish\$Runtime"
$executablePath = Join-Path $publishDirectory "BugNarrator.Windows.exe"

if (-not (Test-Path $executablePath)) {
    throw "Packaged executable was not found: $executablePath"
}

function Get-BugNarratorProcesses {
    return @(Get-Process BugNarrator.Windows -ErrorAction SilentlyContinue)
}

$existingProcesses = Get-BugNarratorProcesses
if ($existingProcesses.Count -gt 0) {
    throw "BugNarrator.Windows is already running. Close it before running single-instance validation."
}

$firstProcess = $null
$secondProcess = $null

try {
    $firstProcess = Start-Process `
        -FilePath $executablePath `
        -WorkingDirectory $publishDirectory `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Seconds $StartupDelaySeconds

    $afterFirstLaunch = Get-BugNarratorProcesses
    if ($afterFirstLaunch.Count -ne 1) {
        throw "Expected exactly one BugNarrator process after first launch, found $($afterFirstLaunch.Count)."
    }

    $secondProcess = Start-Process `
        -FilePath $executablePath `
        -WorkingDirectory $publishDirectory `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Seconds $StartupDelaySeconds
    $secondProcess.Refresh()

    $afterSecondLaunch = Get-BugNarratorProcesses
    if ($afterSecondLaunch.Count -ne 1) {
        throw "Expected exactly one BugNarrator process after duplicate launch, found $($afterSecondLaunch.Count)."
    }

    if (-not $secondProcess.HasExited) {
        throw "Duplicate BugNarrator launch did not exit promptly."
    }

    if ($secondProcess.ExitCode -ne 0) {
        throw "Duplicate BugNarrator launch exited with code $($secondProcess.ExitCode)."
    }

    $result = [PSCustomObject]@{
        runtime = $Runtime
        firstProcessId = $firstProcess.Id
        secondProcessId = $secondProcess.Id
        secondExitCode = $secondProcess.ExitCode
        runningProcessIds = ($afterSecondLaunch | ForEach-Object Id)
        validatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }

    $result | ConvertTo-Json -Depth 4
    Write-Host "Windows single-instance validation passed."
}
finally {
    Get-BugNarratorProcesses | Stop-Process -Force
}
