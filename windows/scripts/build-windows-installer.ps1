[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,
    [string]$OutputRoot = "windows/artifacts",
    [string]$OutputName = "BugNarrator-windows-setup",
    [string]$AppVersion = "0.0.0-dev",
    [string]$InstallerCompilerPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\\..")
$installerScriptPath = Join-Path $repoRoot "windows\\installer\\BugNarrator.iss"
$outputDirectory = Join-Path $repoRoot "$OutputRoot\\installer"
$resolvedPublishDirectory = Resolve-Path $PublishDirectory

function Resolve-InnoSetupCompiler {
    param(
        [string]$OverridePath
    )

    if ($OverridePath) {
        if (Test-Path $OverridePath) {
            return (Resolve-Path $OverridePath).Path
        }

        throw "The Inno Setup compiler path was not found: $OverridePath"
    }

    $command = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $commonPaths = @(
        "${env:ProgramFiles(x86)}\\Inno Setup 6\\ISCC.exe",
        "${env:ProgramFiles}\\Inno Setup 6\\ISCC.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($commonPaths.Count -gt 0) {
        return $commonPaths[0]
    }

    throw "Inno Setup compiler not found. Install Inno Setup 6 or pass -InstallerCompilerPath."
}

if (-not (Test-Path $installerScriptPath)) {
    throw "Installer script not found: $installerScriptPath"
}

if (-not (Test-Path $resolvedPublishDirectory)) {
    throw "Publish directory not found: $PublishDirectory"
}

$compilerPath = Resolve-InnoSetupCompiler -OverridePath $InstallerCompilerPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Push-Location $repoRoot
try {
    & $compilerPath `
        "/DSourceDir=$resolvedPublishDirectory" `
        "/DOutputDir=$outputDirectory" `
        "/DAppVersion=$AppVersion" `
        "/F$OutputName" `
        $installerScriptPath

    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compiler failed."
    }

    $installerPath = Join-Path $outputDirectory "$OutputName.exe"
    if (-not (Test-Path $installerPath)) {
        throw "Installer build completed without producing $installerPath"
    }

    Write-Host "Installer created at $installerPath"
}
finally {
    Pop-Location
}
