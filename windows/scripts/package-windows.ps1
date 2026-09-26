[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts",
    [bool]$SelfContained = $true
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$publishDirectory = Join-Path $repoRoot "$OutputRoot\publish\$Runtime"
$packageDirectory = Join-Path $repoRoot "$OutputRoot\packages"
$packagePath = Join-Path $packageDirectory "BugNarrator-windows-$Runtime.zip"
$publishExecutablePath = Join-Path $publishDirectory "BugNarrator.Windows.exe"

function Stop-RunningPublishedApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    $expectedPath = [System.IO.Path]::GetFullPath($ExecutablePath)
    $runningProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "BugNarrator.Windows.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
            [string]::Equals(
                [System.IO.Path]::GetFullPath($_.ExecutablePath),
                $expectedPath,
                [System.StringComparison]::OrdinalIgnoreCase)
        }

    foreach ($process in $runningProcesses) {
        Write-Warning "Stopping running packaged app from $expectedPath (PID $($process.ProcessId)) before repackaging."
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
    }
}

function Remove-DirectoryWithRetries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$MaxAttempts = 5,
        [int]$DelayMilliseconds = 500
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            if (Test-Path $Path) {
                Remove-Item $Path -Recurse -Force
            }

            return
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw
            }

            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

Push-Location $repoRoot
try {
    if (Test-Path $publishDirectory) {
        Stop-RunningPublishedApp -ExecutablePath $publishExecutablePath
        Remove-DirectoryWithRetries -Path $publishDirectory
    }

    New-Item -ItemType Directory -Force -Path $publishDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null

    dotnet publish "windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj" `
        -c $Configuration `
        -r $Runtime `
        --self-contained $SelfContained `
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
