# Windows local transcription (Parakeet) — design note

Status: proposed (WIN-035, #1169). Design first; no code ships from this ticket.
Depends on WIN-034 (#1168), which already gives Windows the transcription-only
`Local (Parakeet)` provider profile, the `http://localhost:8422` base URL, the
`parakeet-tdt-0.6b-v3` model pin, and the "handles transcription only" rule.

This note reads the macOS managed-server implementation and proposes the
Windows equivalent. The parity matrix row for WIN-035 should be filled from
the "kept identical / deliberately different" table at the end.

## 1. What macOS does today

Sources: `Sources/BugNarrator/Services/LocalTranscriptionManager.swift` (548
lines), `SettingsStore.swift` (reachability probe, lines ~760–815),
`AppLifecycleDelegate.swift` (shutdown), `local-transcription/server.py`,
`local-transcription/build_standalone.sh`.

| Concern | macOS behaviour |
| --- | --- |
| Server | `local-transcription/server.py`: FastAPI + uvicorn, `GET /health` → `{"status":"ok",...}`, `GET /v1/models`, `POST /v1/audio/transcriptions` (OpenAI-compatible multipart). Model loads lazily on first request; inference is serialized on one worker thread; audio is chunked at 120 s. Default port 8422. |
| Inference | `parakeet-mlx` (Apple MLX). **Apple Silicon only** — `build_standalone.sh` refuses non-arm64. |
| Packaging | PyInstaller-style standalone binary `bugnarrator-transcription`, shipped as a signed + notarized DMG release asset (`bugnarrator-transcription-macos-arm64.dmg`, ~136 MB) plus a `.sha256` manifest, on its own release cadence. |
| Discovery of a package | `discover()` pages the GitHub Releases API (≤20 pages × 30) for the first non-draft, non-prerelease release carrying both assets, size-bounded, and only from `https://github.com/ABD-Enterprises/bug-narrator/releases/download/`. |
| Install | Download manifest + image, SHA-256 + size check, `codesign --verify --strict -R <publisher requirement>` on the image and on the binary, `hdiutil attach` read-only, copy to `~/Library/Application Support/BugNarrator/LocalTranscription/`, verify again, atomic move. Install dir must not be a symlink. |
| Launch | Verify the binary's signature again, then run it through `/bin/sh` job control in its own process group (so TERM/KILL reaches uvicorn's children), stdout discarded, stderr captured for the exit message, `Models/` under the install dir as the weights cache. |
| Health / readiness | `SettingsStore` polls `GET {baseURL}/health` every 2 s with a 2 s timeout while the provider is Parakeet; `aiProviderConfigurationIsReady` requires `reachable`. The "Check Server" button uses the same probe. The typed base URL is ignored for Parakeet. |
| Stop / shutdown | `stop()` on `NSApplication.willTerminate`; `shutdown()` awaits in-flight install/start and then the process exit. TERM, 2 s grace for uvicorn to drain an in-flight request, then KILL (#1128). |
| Remove | Deletes the install dir including the model cache. |
| Already-running server | Not launched by BugNarrator: nothing special — the health probe simply reports reachable, and the app never starts a second copy because `start()` requires `installed && server == nil`. It does **not** adopt or stop a foreign server. |
| Failure surface | `message` string in Settings (download failed, checksum failed, verification failed, exited with status N + stderr tail). |

## 2. Constraints that differ on Windows

1. **No MLX.** `parakeet-mlx` cannot run on Windows. The same NVIDIA
   `parakeet-tdt-0.6b-v3` weights are published in ONNX form and run on CPU
   (and DirectML/CUDA where present) through `onnxruntime`; `sherpa-onnx` and
   `onnx-asr` both ship ready TDT decoders. The server *protocol* stays the
   same; the inference backend does not.
2. **No code-signing verify primitive equivalent to `codesign -R`.** Windows
   has Authenticode; the tester zip is already signed with the project's
   Azure Trusted Signing identity (`.github/workflows/*windows*`). A signed
   server executable can be verified with `WinVerifyTrust` /
   `X509Certificate.GetCertHash` against a pinned publisher thumbprint. No
   DMG, no `hdiutil`: the asset is a zip.
3. **Packaging is a signed tester zip, no installer.** There is no
   `Application Support` install step today; the app runs from wherever the
   zip was extracted. The server must therefore install into
   `%LOCALAPPDATA%\BugNarrator\LocalTranscription\`, not next to the app.
4. **Process groups do not exist.** The `/bin/sh` job-control dance is
   replaced by a Windows Job Object with `KILL_ON_JOB_CLOSE`, so uvicorn and
   any child it spawns die with BugNarrator even on a crash.
5. **Firewall prompt.** A new listener on 127.0.0.1 does not trigger the
   Windows Defender Firewall prompt (loopback is exempt), provided the server
   binds `127.0.0.1` rather than `0.0.0.0`. `server.py` already defaults
   `--host` to `127.0.0.1`; the Windows launch passes it explicitly so a
   future default change cannot widen the bind.
6. **Size.** A CPU ONNX build (onnxruntime + weights ~600 MB fp32, ~300 MB
   int8) is larger than the 136 MB MLX bundle. The weights should be
   downloaded by the server on first request (as macOS already does into
   `Models/`), keeping the executable itself under ~80 MB.

## 3. Proposed Windows design

### 3.1 Components

```
BugNarrator.Windows.Services/LocalTranscription/
  ILocalTranscriptionServerManager      (state machine + operations, testable)
  LocalTranscriptionServerManager       (live)
  LocalServerHealthProbe                (GET /health, 2 s timeout, 2 s cadence)
  LocalServerPackageCatalog             (GitHub Releases discovery, size/URL bounded)
  LocalServerInstaller                  (download, SHA-256, Authenticode verify, atomic move)
  LocalServerProcess                    (Process + Job Object, stderr tail, TERM→KILL grace)
local-transcription/
  server.py                             (unchanged protocol; backend selected by platform)
  build_standalone_windows.ps1          (PyInstaller onefile, signed by the release workflow)
```

`LocalTranscriptionServerManager` is a state machine with the same observable
shape as the macOS `@Published` set: `Package?`, `Progress?`, `Busy`,
`Installed`, `Running`, `Message`. Settings binds to it exactly as
`SettingsAudioPanes.swift` does.

### 3.2 Discovery of an already-running server at 8422

Kept identical to macOS: the manager never adopts a foreign process. The
health probe (`GET http://127.0.0.1:8422/health`, 2 s timeout, polled every
2 s while the provider is Parakeet, and on "Check Server") is the only
readiness signal. If something else answers `{"status":"ok"}` on 8422 the app
is ready and does not try to start its own copy; `Start` stays disabled
while `Running == false && reachable == true` with the message "A local
transcription server is already responding on port 8422." This matches macOS
where `start()` is a no-op only because the user would not press it, and
makes the rule explicit.

Port is fixed at 8422 (the profile's base URL), as on macOS. A user-provided
base URL is ignored for Parakeet (WIN-034 already pins it).

### 3.3 Optional launch of a user-installed server

Two install sources, in priority order:

1. **Managed install** (default path, mirrors macOS): download the signed
   release asset `bugnarrator-transcription-windows-x64.zip` + `.sha256`
   from the pinned GitHub Releases path, verify, extract to
   `%LOCALAPPDATA%\BugNarrator\LocalTranscription\`, launch.
2. **Developer/user-installed server** (Windows-only addition): if
   `%LOCALAPPDATA%\BugNarrator\LocalTranscription\bugnarrator-transcription.exe`
   exists but no package metadata does, treat it as installed and launch it
   *only after* Authenticode verification passes. Unsigned binaries are
   refused with "The local server executable is not signed by the BugNarrator
   publisher. Remove and reinstall it." — same posture as macOS `verifyBinary`.

Launch: `bugnarrator-transcription.exe --host 127.0.0.1 --port 8422
--model parakeet-tdt-0.6b-v3`, working directory = install dir,
`HF_HOME`/model cache = `<install dir>\Models`, stdout discarded, stderr
captured (last 4 KB) for the exit message, process assigned to a Job Object
with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.

### 3.4 Health check

Identical to macOS: `GET /health` must return HTTP 200 with JSON
`status == "ok"`. 2 s timeout, no caching, 2 s cadence, only while the
provider is Parakeet. `aiProviderConfigurationIsReady` for Parakeet =
no compatibility issue **and** reachable. Recording start (the
`RecordingLifecycleService` preflight) refuses with the existing
"Finish AI provider setup" path when unreachable, so audio is never
recorded into a session that cannot be transcribed — this is the
"fail before transcription starts" rule of the product spec.

### 3.5 Shutdown grace

Identical to macOS (#1128): on app exit send a graceful stop, wait 2 s for
uvicorn to drain an in-flight request, then terminate. Windows has no
SIGTERM for console processes we did not create as a console; the graceful
signal is `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT)` on the process group
created with `CREATE_NEW_PROCESS_GROUP` (uvicorn handles it as SIGBREAK →
graceful shutdown), then `Process.Kill(entireProcessTree: true)` after 2 s,
and the Job Object closes last as the backstop. `WindowsAppShell.Dispose`
awaits `ShutdownAsync()` before `Application.Shutdown` completes, the way
`AppLifecycleDelegate.shutdown` does.

### 3.6 What the packaging must ship

- A new release asset built by a Windows runner: PyInstaller onefile
  `bugnarrator-transcription.exe` from `server.py` with the ONNX backend
  (`onnxruntime` CPU; DirectML optional later), zipped as
  `bugnarrator-transcription-windows-x64.zip` with a sibling `.sha256`
  manifest, signed with the same Azure Trusted Signing identity as the app.
- `server.py` gains a backend switch: `parakeet-mlx` on macOS, ONNX
  elsewhere. Protocol, model aliases (`parakeet`, `whisper-1`, …), chunking
  and the failure message stay byte-identical so the shared
  `contract-fixtures` keep passing.
- Weights are **not** in the zip; the server downloads them into `Models\`
  on first request (same first-start message as macOS: "The first start
  downloads model weights; recording becomes ready when the server
  responds.").
- The release workflow publishes the Windows server asset on the same
  independent cadence as the macOS DMG; the app discovers it by name.

### 3.7 Removal

Identical: deletes the install dir including `Models\`, only when not busy
and not running.

## 4. Kept identical vs. deliberately different

| Behaviour | Decision | Reason |
| --- | --- | --- |
| Server HTTP protocol (`/health`, `/v1/models`, `/v1/audio/transcriptions`), port 8422, model aliases, chunking, failure message | Identical | Client code and contract fixtures are shared; WIN-034 already pins the URL and model. |
| Health probe semantics (2 s timeout, 2 s cadence, `status == "ok"`), readiness = reachable | Identical | Same "fail before transcription" guarantee. |
| No adoption of a foreign server; never start a second copy when 8422 answers | Identical (made explicit in UI) | Same safety posture; explicit message avoids a silent no-op. |
| Signed-asset discovery bounded to the project's GitHub Releases download path, size caps, checksum manifest | Identical | Supply-chain posture must not be weaker on Windows. |
| Publisher verification before install and before every launch | Identical in intent | Mechanism differs: Authenticode thumbprint pin instead of `codesign -R`. |
| TERM → 2 s grace → KILL on exit; app waits for exit | Identical in intent | Mechanism differs: `CTRL_BREAK` + `Kill(tree)` + Job Object instead of process-group signals. |
| Install location | Different | `%LOCALAPPDATA%\BugNarrator\LocalTranscription\` — the app has no bundle/Application Support of its own; must survive re-extracting the tester zip. |
| Inference backend | Different | MLX is Apple-only; ONNX Runtime (CPU, optional DirectML) runs the same `parakeet-tdt-0.6b-v3` weights. Accuracy is the same model; throughput on CPU is lower and is a documented expectation, not a bug. |
| Asset format | Different | zip instead of DMG; no `hdiutil`. |
| Bind address | Identical (`127.0.0.1`), passed explicitly | Loopback-only keeps audio local and avoids the firewall prompt; the explicit flag pins it regardless of the server default. |
| Architecture support | Different | macOS: Apple Silicon only. Windows: x64 first; arm64 deferred until onnxruntime wheels are proven. |
| "User-installed server" path | Windows addition | Lets testers drop a signed exe in place before the release asset exists; refused unless signed. |

## 5. Open questions for the panel

1. **Backend**: `sherpa-onnx` (C++ core, ships TDT decoding, Windows wheels) vs.
   `onnx-asr` (pure Python, simpler to bundle). Recommendation: `onnx-asr`
   for the first release; revisit if CPU latency on the 120 s chunks is
   unacceptable.
2. **Trust anchor**: pin the Azure Trusted Signing leaf thumbprint (rotates
   on renewal) or the issuing CA + subject (`ABD Enterprises`)?
   Recommendation: subject + issuer chain to the Microsoft Identity
   Verification root, as macOS pins the team OU rather than a leaf.
3. **First deliverable order**: (a) server build + release asset, then (b)
   manager + Settings, then (c) shutdown wiring. (a) can be validated with
   `smoke_test.sh` semantics ported to PowerShell before any app code.

## 6. Implementation tickets to file from this note

- WIN-036 — `server.py` ONNX backend switch + Windows PyInstaller build +
  signed zip release asset + PowerShell smoke test (packaging only).
- WIN-037 — `LocalTranscriptionServerManager` state machine, package
  catalog, installer with Authenticode verification, tests with a fake
  process/HTTP.
- WIN-038 — Health probe + readiness gate in `WindowsAppSettings` /
  `RecordingLifecycleService` preflight, Settings "Check Server" wiring,
  Parakeet section of Settings (install / start / stop / remove, messages).
- WIN-039 — Process launch with Job Object, graceful shutdown on app exit,
  `WindowsAppShell` shutdown wait; parity-matrix row flips to In Progress.
