[CmdletBinding()]
param(
    [switch]$RunBaseline,
    [string]$OutputRoot = "windows/artifacts"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$reportDirectory = Join-Path $repoRoot "$OutputRoot\handoff"
$reportPath = Join-Path $reportDirectory "windows-codex-handoff.json"
$phaseStatePath = Join-Path $repoRoot "docs/roadmap/state.json"
$sessionStatePath = Join-Path $repoRoot "state/session.json"
$taskStatePath = Join-Path $repoRoot "state/tasks.json"
$riskStatePath = Join-Path $repoRoot "state/risks.json"
$decisionStatePath = Join-Path $repoRoot "state/decisions.json"

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Content $Path -Raw | ConvertFrom-Json
}

function Get-RelativeRepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.Path]::GetRelativePath($repoRoot, $Path).Replace('\', '/')
}

function Get-GitValue {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        return $null
    }

    $result = & $gitCommand.Source -C $repoRoot @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $value = ($result | Out-String).Trim()
    return [string]::IsNullOrWhiteSpace($value) ? $null : $value
}

function Invoke-BaselineStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$CommandText,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[object]]$StepResults
    )

    $step = [ordered]@{
        name = $Name
        command = $CommandText
        startedAt = (Get-Date).ToUniversalTime().ToString("o")
        status = "running"
    }

    try {
        & $Action
        $step.status = "passed"
    }
    catch {
        $step.status = "failed"
        $step.error = $_.Exception.Message
        throw
    }
    finally {
        $step.finishedAt = (Get-Date).ToUniversalTime().ToString("o")
        $StepResults.Add([PSCustomObject]$step)
    }
}

$phaseState = Read-JsonFile -Path $phaseStatePath
$sessionState = Read-JsonFile -Path $sessionStatePath
$taskState = Read-JsonFile -Path $taskStatePath
$riskState = Read-JsonFile -Path $riskStatePath
$decisionState = Read-JsonFile -Path $decisionStatePath

$currentPhase = $phaseState.current_phase
$currentPhaseId = $currentPhase.id
$currentBranch = Get-GitValue -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
$headCommit = Get-GitValue -Arguments @("rev-parse", "HEAD")
$phaseTasks = @($taskState.active | Where-Object { $_.phase -eq $currentPhaseId })
$phaseCompletedTasks = @($taskState.completed | Where-Object { $_.phase -eq $currentPhaseId })
$phaseRisks = @($riskState.unresolved | Where-Object { $_.assigned_phase -eq $currentPhaseId })
$allUnresolvedRisks = @($riskState.unresolved)
$phaseDecisions = @($decisionState.entries | Where-Object { $_.phase -eq $currentPhaseId } | Select-Object -Last 5)
$windowsArtifacts = @(
    (Join-Path $repoRoot "windows/artifacts/packages/BugNarrator-windows-win-x64.zip")
    (Join-Path $repoRoot "windows/artifacts/validation/BugNarrator-windows-win-x64-validation.json")
    (Join-Path $repoRoot "windows/artifacts/publish/win-x64/bugnarrator-smoke-report.json")
)
$artifactSnapshot = foreach ($artifactPath in $windowsArtifacts) {
    [PSCustomObject]@{
        path = Get-RelativeRepoPath -Path $artifactPath
        exists = Test-Path $artifactPath
    }
}

$baselineState = [ordered]@{
    requested = [bool]$RunBaseline
    executed = $false
    overallStatus = if ($RunBaseline) { "pending" } else { "not_run" }
    steps = [System.Collections.Generic.List[object]]::new()
}

$baselineError = $null

if ($RunBaseline) {
    if (-not $IsWindows) {
        throw "The -RunBaseline option requires a Windows machine because the WPF shell and package validation cannot be honestly executed elsewhere."
    }

    $baselineState.executed = $true

    try {
        Invoke-BaselineStep `
            -Name "build" `
            -CommandText "powershell -ExecutionPolicy Bypass -File windows/scripts/build-windows.ps1 -Configuration Debug" `
            -Action { & (Join-Path $repoRoot "windows/scripts/build-windows.ps1") -Configuration Debug } `
            -StepResults $baselineState.steps

        Invoke-BaselineStep `
            -Name "test" `
            -CommandText "powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug" `
            -Action { & (Join-Path $repoRoot "windows/scripts/test-windows.ps1") -Configuration Debug } `
            -StepResults $baselineState.steps

        Invoke-BaselineStep `
            -Name "package" `
            -CommandText "powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release" `
            -Action { & (Join-Path $repoRoot "windows/scripts/package-windows.ps1") -Configuration Release } `
            -StepResults $baselineState.steps

        Invoke-BaselineStep `
            -Name "validate_package" `
            -CommandText "powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64" `
            -Action { & (Join-Path $repoRoot "windows/scripts/validate-windows-package.ps1") -Runtime win-x64 } `
            -StepResults $baselineState.steps

        $baselineState.overallStatus = "passed"
    }
    catch {
        $baselineState.overallStatus = "failed"
        $baselineError = $_
    }
}

New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null

$report = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    repository = [ordered]@{
        branch = $currentBranch
        headCommit = $headCommit
        currentPhaseBranch = $phaseState.current_phase_branch
    }
    environment = [ordered]@{
        isWindows = [bool]$IsWindows
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        outputRoot = Get-RelativeRepoPath -Path (Join-Path $repoRoot $OutputRoot)
    }
    phase = [ordered]@{
        id = $currentPhase.id
        name = $currentPhase.name
        status = $currentPhase.status
        summary = $currentPhase.summary
        sessionSummary = $sessionState.execution_summary
    }
    activeTasks = @($phaseTasks | ForEach-Object {
        [PSCustomObject]@{
            id = $_.id
            title = $_.title
            blocking_for_phase_completion = [bool]$_.blocking_for_phase_completion
        }
    })
    recentlyCompletedTasks = @($phaseCompletedTasks | Select-Object -Last 3 | ForEach-Object {
        [PSCustomObject]@{
            id = $_.id
            title = $_.title
        }
    })
    unresolvedPhaseRisks = @($phaseRisks)
    allUnresolvedRisks = @($allUnresolvedRisks)
    opportunities = @($phaseState.opportunities)
    latestDecisions = @($phaseDecisions)
    sourceDocs = @(
        "docs/architecture/product-spec.md",
        "docs/roadmap/state.json",
        "state/session.json",
        "state/tasks.json",
        "state/risks.json",
        "windows/README.md",
        "windows/docs/WINDOWS_CODEX_HANDOFF.md",
        "windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md",
        "windows/docs/WINDOWS_VALIDATION_CHECKLIST.md"
    )
    recommendedCommands = [ordered]@{
        baseline = @(
            "powershell -ExecutionPolicy Bypass -File windows/scripts/invoke-windows-codex-handoff.ps1 -RunBaseline",
            "dotnet run --project windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug"
        )
        manualValidation = @(
            "Validate RR-002-T4 tray, recording, screenshot, and hotkey behavior on a real Windows desktop or VM.",
            "Update docs/roadmap/state.json and state/*.json after real Windows findings land.",
            "Update windows/docs/WINDOWS_VALIDATION_CHECKLIST.md and windows/README.md if runtime findings change the expected behavior."
        )
    }
    artifacts = @($artifactSnapshot)
    baseline = [PSCustomObject]$baselineState
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath

Write-Host "Windows Codex handoff report written to $reportPath"

if ($baselineError) {
    throw $baselineError
}
