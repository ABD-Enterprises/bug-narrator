<#
.SYNOPSIS
Build the standalone Windows binary of the BugNarrator transcription server.

.DESCRIPTION
The Windows counterpart of build_standalone.sh: a hash-locked build venv, PyInstaller onefile,
and a zip + SHA-256 manifest the app's LocalServerPackageCatalog / LocalServerInstaller consume
(docs/architecture/windows-local-transcription.md). Model weights are not bundled; the server
downloads them on first request into the Models directory beside the executable (HF_HOME, which
the app sets when it launches the server).

Output: <OutputDir>\bugnarrator-transcription-windows-<arch>.zip and .sha256, plus
<OutputDir>\bugnarrator-transcription.exe for local smoke tests. Signing is a separate step
(windows/scripts/sign-windows*.ps1) that the release workflow runs on the exe before zipping.

.PARAMETER Arch
x64 (the shipped asset) or arm64 (for running on an ARM64 Windows machine). The build always
targets the architecture of the Python that runs it; the parameter names the asset.
#>
[CmdletBinding()]
param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Python = "python",
    [string]$OutputDir = "",
    [switch]$SkipPipCheck,
    # Package only: zip the (already signed) exe in OutputDir and write the .sha256 manifest.
    [switch]$PackageOnly
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$appName = "bugnarrator-transcription"
$assetName = "$appName-windows-$Arch"
$buildVenv = Join-Path $scriptDir "build\standalone-venv-windows"
# One hash lock per target: resolved with uv for x86_64-pc-windows-msvc and aarch64-pc-windows-msvc.
$lock = Join-Path $scriptDir $(if ($Arch -eq "arm64") { "requirements-windows-arm64.lock" } else { "requirements-windows.lock" })
$distDir = Join-Path $scriptDir "dist"
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot "dist" }
$version = (Get-Content (Join-Path $repoRoot "VERSION") -Raw).Trim()
$releaseCommit = (& git -C $repoRoot rev-parse HEAD 2>$null); if (-not $releaseCommit) { $releaseCommit = "unknown" }

function Write-Package {
    # The zip carries the exe at its root — LocalServerInstaller extracts exactly that entry —
    # and the manifest is "<sha256 hex>  <asset name>", the same shape as the macOS .sha256.
    $exePath = Join-Path $OutputDir "$appName.exe"
    if (-not (Test-Path $exePath)) { throw "No executable to package at $exePath" }
    $zipPath = Join-Path $OutputDir "$assetName.zip"
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    Compress-Archive -Path $exePath -DestinationPath $zipPath -CompressionLevel Optimal
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $assetName.zip`n" | Set-Content -Path "$zipPath.sha256" -Encoding ascii -NoNewline
    Write-Host "Packaged $zipPath ($((Get-Item $zipPath).Length) bytes, sha256 $hash)"
}

if ($PackageOnly) {
    Write-Package
    exit 0
}

$machine = & $Python -c "import platform; print(platform.machine().lower())"
$expectedMachine = if ($Arch -eq "x64") { "amd64" } else { "arm64" }
if ($machine -ne $expectedMachine) {
    throw "Building the $Arch asset requires a $expectedMachine Python; this interpreter reports '$machine'."
}

Write-Host "Creating the build environment..."
& $Python -m venv $buildVenv
$venvPython = Join-Path $buildVenv "Scripts\python.exe"
& $venvPython -m pip install --quiet --disable-pip-version-check --require-hashes --only-binary=:all: -r $lock
if ($LASTEXITCODE -ne 0) { throw "pip install from the hash-locked requirements failed." }

if (-not $SkipPipCheck) {
    & $venvPython -m pip check
    if ($LASTEXITCODE -ne 0) { throw "pip check reported broken dependencies." }
}

$pyinstallerVersion = & $venvPython -c "from importlib.metadata import version; print(version('pyinstaller'))"

Write-Host "Building standalone binary..."
& $venvPython -m PyInstaller `
    --name $appName `
    --onefile `
    --noconfirm `
    --clean `
    --distpath $distDir `
    --workpath (Join-Path $scriptDir "build\pyinstaller-windows") `
    --specpath (Join-Path $scriptDir "build\pyinstaller-windows") `
    --collect-all onnx_asr `
    --collect-all onnxruntime `
    --hidden-import uvicorn.logging `
    --hidden-import uvicorn.loops `
    --hidden-import uvicorn.loops.auto `
    --hidden-import uvicorn.protocols `
    --hidden-import uvicorn.protocols.http `
    --hidden-import uvicorn.protocols.http.auto `
    --hidden-import uvicorn.protocols.websockets `
    --hidden-import uvicorn.protocols.websockets.auto `
    --hidden-import uvicorn.lifespan `
    --hidden-import uvicorn.lifespan.on `
    --hidden-import multipart `
    (Join-Path $scriptDir "server.py")
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed." }

$exe = Join-Path $distDir "$appName.exe"
if (-not (Test-Path $exe)) { throw "PyInstaller did not produce $exe" }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Copy-Item $exe (Join-Path $OutputDir "$appName.exe") -Force

# Provenance beside the exe, as build_standalone.sh records for the DMG.
@{
    name = $assetName
    version = $version
    commit = $releaseCommit
    python = (& $venvPython -c "import sys; print(sys.version.split()[0])")
    pyinstaller = $pyinstallerVersion
    backend = "onnx-asr"
    built_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content -Path (Join-Path $OutputDir "$assetName-build.json") -Encoding utf8

Write-Host "Built $exe (PyInstaller $pyinstallerVersion, version $version)"
