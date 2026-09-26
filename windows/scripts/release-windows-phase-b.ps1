[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$OutputRoot = "windows/artifacts",
    [string]$ReleaseLabel = "phase-b-public-candidate",
    [string]$InstallerCompilerPath = "",
    [string]$SignToolPath = "signtool.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\\..")
$releaseRoot = Join-Path $repoRoot "$OutputRoot\\releases\\public\\$ReleaseLabel"
$publishDirectory = Join-Path $repoRoot "$OutputRoot\\publish\\$Runtime"
$packagePath = Join-Path $repoRoot "$OutputRoot\\packages\\BugNarrator-windows-$Runtime.zip"
$installerOutputDirectory = Join-Path $repoRoot "$OutputRoot\\installer"
$manifestPath = Join-Path $releaseRoot "public-release-status.json"
$checksumsPath = Join-Path $releaseRoot "checksums.txt"

function Add-Blocker {
    param(
        [System.Collections.Generic.List[string]]$Blockers,
        [string]$Message
    )

    if (-not $Blockers.Contains($Message)) {
        $Blockers.Add($Message) | Out-Null
    }
}

function Try-ResolveCommand {
    param(
        [string]$CommandName
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    return $command?.Source
}

function Get-VersionLabel {
    param(
        [string]$ExecutablePath
    )

    if (-not (Test-Path $ExecutablePath)) {
        return "0.0.0-dev"
    }

    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExecutablePath).ProductVersion
    if ([string]::IsNullOrWhiteSpace($version)) {
        return "0.0.0-dev"
    }

    return $version.Trim()
}

function Write-Checksums {
    param(
        [string[]]$Paths,
        [string]$DestinationPath
    )

    $lines = foreach ($path in $Paths) {
        if (Test-Path $path) {
            $hash = Get-FileHash $path -Algorithm SHA256
            "$($hash.Hash)  $(Split-Path $path -Leaf)"
        }
    }

    if ($lines.Count -gt 0) {
        Set-Content -Path $DestinationPath -Value $lines
    }
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
$blockers = New-Object 'System.Collections.Generic.List[string]'
$artifacts = New-Object 'System.Collections.Generic.List[object]'
$installerPath = $null
$signedExecutable = $false
$signedInstaller = $false
$signToolResolvedPath = Try-ResolveCommand -CommandName $SignToolPath

Push-Location $repoRoot
try {
    & powershell -ExecutionPolicy Bypass -File "windows/scripts/build-windows.ps1" -Configuration $Configuration
    & powershell -ExecutionPolicy Bypass -File "windows/scripts/test-windows.ps1" -Configuration $Configuration
    & powershell -ExecutionPolicy Bypass -File "windows/scripts/package-windows.ps1" -Configuration $Configuration -Runtime $Runtime

    if (Test-Path $packagePath) {
        Copy-Item $packagePath (Join-Path $releaseRoot (Split-Path $packagePath -Leaf)) -Force
        $artifacts.Add([pscustomobject]@{
            kind = "trusted_tester_zip"
            path = (Join-Path $releaseRoot (Split-Path $packagePath -Leaf))
        }) | Out-Null
    }

    if (-not $InstallerCompilerPath) {
        $resolvedIscc = Try-ResolveCommand -CommandName "iscc.exe"
        if (-not $resolvedIscc) {
            $possiblePaths = @(
                "${env:ProgramFiles(x86)}\\Inno Setup 6\\ISCC.exe",
                "${env:ProgramFiles}\\Inno Setup 6\\ISCC.exe"
            ) | Where-Object { $_ -and (Test-Path $_) }

            if ($possiblePaths.Count -gt 0) {
                $resolvedIscc = $possiblePaths[0]
            }
        }

        if ($resolvedIscc) {
            $InstallerCompilerPath = $resolvedIscc
        }
    }

    if (-not $InstallerCompilerPath) {
        Add-Blocker $blockers "Inno Setup is not installed. Install Inno Setup 6 or pass -InstallerCompilerPath before building the public installer."
    }

    if (-not $signToolResolvedPath) {
        Add-Blocker $blockers "signtool.exe is not available on PATH. Install the Windows SDK signing tools or pass -SignToolPath."
    }

    if (-not $env:BUGNARRATOR_CERT_PATH) {
        Add-Blocker $blockers "BUGNARRATOR_CERT_PATH is not set for public Windows signing."
    }
    elseif (-not (Test-Path $env:BUGNARRATOR_CERT_PATH)) {
        Add-Blocker $blockers "BUGNARRATOR_CERT_PATH does not point to an existing certificate file."
    }

    if (-not $env:BUGNARRATOR_CERT_PASSWORD) {
        Add-Blocker $blockers "BUGNARRATOR_CERT_PASSWORD is not set for public Windows signing."
    }

    if ($blockers.Count -eq 0) {
        $versionLabel = Get-VersionLabel -ExecutablePath (Join-Path $publishDirectory "BugNarrator.Windows.exe")
        & powershell -ExecutionPolicy Bypass -File "windows/scripts/build-windows-installer.ps1" `
            -PublishDirectory $publishDirectory `
            -OutputRoot $OutputRoot `
            -OutputName "BugNarrator-windows-$Runtime-setup" `
            -AppVersion $versionLabel `
            -InstallerCompilerPath $InstallerCompilerPath

        $installerPath = Join-Path $installerOutputDirectory "BugNarrator-windows-$Runtime-setup.exe"
        if (-not (Test-Path $installerPath)) {
            throw "Installer build reported success but the expected installer was not found: $installerPath"
        }

        & powershell -ExecutionPolicy Bypass -File "windows/scripts/sign-windows.ps1" `
            -FilePath (Join-Path $publishDirectory "BugNarrator.Windows.exe") `
            -SignToolPath $signToolResolvedPath
        $signedExecutable = $true

        & powershell -ExecutionPolicy Bypass -File "windows/scripts/sign-windows.ps1" `
            -FilePath $installerPath `
            -SignToolPath $signToolResolvedPath
        $signedInstaller = $true

        Copy-Item $installerPath (Join-Path $releaseRoot (Split-Path $installerPath -Leaf)) -Force
        $artifacts.Add([pscustomobject]@{
            kind = "public_installer"
            path = (Join-Path $releaseRoot (Split-Path $installerPath -Leaf))
        }) | Out-Null
    }

    $releaseArtifacts = Get-ChildItem $releaseRoot -File | Select-Object -ExpandProperty FullName
    Write-Checksums -Paths $releaseArtifacts -DestinationPath $checksumsPath

    $status = if ($blockers.Count -eq 0) { "ready" } else { "blocked" }
    $manifest = [pscustomobject]@{
        generatedAt = [DateTimeOffset]::UtcNow.ToString("O")
        status = $status
        releaseLabel = $ReleaseLabel
        configuration = $Configuration
        runtime = $Runtime
        installerTechnology = "Inno Setup"
        publishDirectory = $publishDirectory
        trustedTesterPackage = if (Test-Path $packagePath) { $packagePath } else { $null }
        installerPath = $installerPath
        signedExecutable = $signedExecutable
        signedInstaller = $signedInstaller
        blockers = $blockers.ToArray()
        artifacts = $artifacts.ToArray()
    }

    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath

    if ($status -eq "blocked") {
        Write-Warning "Phase B public release remains blocked."
        Write-Warning (($blockers -join [Environment]::NewLine))
    }
    else {
        Write-Host "Phase B public release artifacts are staged at $releaseRoot"
    }
}
finally {
    Pop-Location
}
