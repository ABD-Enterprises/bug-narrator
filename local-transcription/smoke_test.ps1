<#
.SYNOPSIS
Smoke-test a packaged Windows transcription server, mirroring smoke_test.sh.

.DESCRIPTION
Starts the exe on 127.0.0.1 with --preload, waits for GET /health to report status ok with the
model loaded (the first run downloads the weights into a scratch HF_HOME), checks GET /v1/models
lists the model, POSTs a synthesized WAV and requires a non-empty transcript containing the
spoken words, then stops the server with Ctrl+Break and requires it to exit within the 2 s grace
the app allows. Writes a smoke-test log next to the response for CI evidence.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerBinary,
    [int]$Port = 0,
    [int]$PreloadTimeoutSeconds = 900,
    [string]$LogDir = ""
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $ServerBinary)) { throw "Server binary not found: $ServerBinary" }
$smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bugnarrator-transcription-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
if (-not $LogDir) { $LogDir = $smokeRoot }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$serverLog = Join-Path $LogDir "server.log"
$smokeLog = Join-Path $LogDir "smoke-test.log"
$responsePath = Join-Path $LogDir "transcription.json"
$audioPath = Join-Path $smokeRoot "fixture.wav"
$phrase = "Bug Narrator local transcription is ready."

function Log($message) {
    $line = "$((Get-Date).ToUniversalTime().ToString('o')) $message"
    Write-Host $line
    Add-Content -Path $smokeLog -Value $line
}

if ($Port -eq 0) {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start(); $Port = $listener.LocalEndpoint.Port; $listener.Stop()
}

# The fixture is synthesized by Windows speech (the smoke_test.sh `say` equivalent) as 16 kHz
# 16-bit mono PCM — the format BugNarrator's Windows recorder produces.
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$synth.SetOutputToWaveFile($audioPath, $format)
$synth.Speak($phrase)
$synth.Dispose()
Log "fixture: $audioPath ($((Get-Item $audioPath).Length) bytes)"

# HF_HOME under the scratch root unless the caller provided one (CI caches it across runs).
if (-not $env:HF_HOME) { $env:HF_HOME = Join-Path $smokeRoot "Models" }
Log "model cache: $env:HF_HOME"

# Started the way the app starts it: in its own (hidden) console, stderr to a file. A hidden
# console — not CreateNoWindow — is what lets the graceful Ctrl+C reach the server later.
$server = Start-Process -FilePath (Resolve-Path $ServerBinary).Path `
    -ArgumentList "--host 127.0.0.1 --port $Port --preload" `
    -WindowStyle Hidden -RedirectStandardError $serverLog -PassThru
Log "server pid $($server.Id) on port $Port"
# PyInstaller onefile runs the real interpreter as a child of the bootloader; a stop must take
# both, so the child is tracked from the start.
Start-Sleep -Milliseconds 1500
$children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($server.Id)" | Select-Object -ExpandProperty ProcessId)
Log "server child process(es): $($children -join ', ')"

try {
    $health = $null
    $deadline = (Get-Date).AddSeconds($PreloadTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($server.HasExited) { throw "packaged transcription server exited before becoming healthy (code $($server.ExitCode))" }
        try { $health = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 2 } catch { $health = $null }
        if ($health -and $health.status -eq "ok" -and $health.model_loaded) { break }
        Start-Sleep -Seconds 1
    }
    if (-not ($health -and $health.status -eq "ok" -and $health.model_loaded)) {
        throw "packaged transcription server did not preload within $PreloadTimeoutSeconds seconds"
    }
    Log "health: $($health | ConvertTo-Json -Compress)"

    $models = Invoke-RestMethod "http://127.0.0.1:$Port/v1/models" -TimeoutSec 5
    if (-not ($models.data | Where-Object { $_.id -like "*parakeet*" })) { throw "/v1/models did not list the Parakeet model: $($models | ConvertTo-Json -Compress)" }
    Log "models: $($models | ConvertTo-Json -Compress)"

    $status = & curl.exe --silent --show-error --max-time 300 --output $responsePath --write-out "%{http_code}" `
        --form "file=@$audioPath" --form "model=parakeet-tdt-0.6b-v3" --form "response_format=verbose_json" `
        "http://127.0.0.1:$Port/v1/audio/transcriptions"
    if ($status -ne "200") { throw "packaged transcription request returned HTTP ${status}: $(Get-Content $responsePath -Raw)" }
    $response = Get-Content $responsePath -Raw | ConvertFrom-Json
    $text = ($response.text -as [string]).Trim().ToLowerInvariant()
    Log "transcript: '$($response.text)' ($($response.segments.Count) segment(s))"
    if (-not $text) { throw "packaged transcription returned an empty transcript" }
    foreach ($word in @("narrator", "transcription", "ready")) {
        if ($text -notlike "*$word*") { throw "transcript is missing '$word': $text" }
    }
    if ($response.segments.Count -lt 1 -or $response.segments[0].end -le 0) { throw "transcript has no timed segments" }

    # Stop the way the app does (LocalServerProcess): Ctrl+C on the server's own console, then
    # require exit inside the 2 s grace. A helper process does the signalling because attaching
    # to another console means giving up this script's own.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $signalScript = @'
param([uint32]$TargetPid)
Add-Type -Namespace Smoke -Name Console -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint pid);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
"@
[Smoke.Console]::FreeConsole() | Out-Null
if (-not [Smoke.Console]::AttachConsole($TargetPid)) { exit 2 }
[Smoke.Console]::SetConsoleCtrlHandler([IntPtr]::Zero, $true) | Out-Null
$sent = [Smoke.Console]::GenerateConsoleCtrlEvent(0, 0)
Start-Sleep -Milliseconds 300
[Smoke.Console]::FreeConsole() | Out-Null
exit $(if ($sent) { 0 } else { 3 })
'@
    $signalPath = Join-Path $smokeRoot "send-ctrl-c.ps1"
    Set-Content -Path $signalPath -Value $signalScript -Encoding utf8
    $signaller = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $signalPath, "-TargetPid", $server.Id -WindowStyle Hidden -PassThru -Wait
    $signalled = ($signaller.ExitCode -eq 0)
    if (-not $server.WaitForExit(2000)) {
        Log "server ignored the graceful stop (signalled=$signalled); killing"
        $server.Kill($true)
        $server.WaitForExit()
        throw "packaged transcription server did not stop within the 2 s grace"
    }
    Log "server stopped in $($stopwatch.ElapsedMilliseconds) ms"
    Start-Sleep -Milliseconds 500
    $survivors = @($children | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    if ($survivors.Count -gt 0) {
        foreach ($survivor in $survivors) { Stop-Process -Id $survivor -Force -ErrorAction SilentlyContinue }
        throw "the bootloader exited but its interpreter child survived: $($survivors -join ', ')"
    }
    Log "smoke test passed"
}
catch {
    Log "FAILED: $($_.Exception.Message)"
    if (-not $server.HasExited) { $server.Kill($true); $server.WaitForExit() }
    foreach ($child in $children) { Stop-Process -Id $child -Force -ErrorAction SilentlyContinue }
    throw
}
finally {
    Log "server log: $serverLog"
}
