# Critical Review — ABD-Enterprises/bug-narrator

**Date:** 2026-10-29
**Commit reviewed:** `c8c0070` (local `main`, fast-forwarded from `4981148`; upstream `origin/main` was 3 commits ahead on fetch)
**Status:** snapshot. `main` moved during and after the review; findings are checked against the commit named above, and any finding affected by a later commit is called out in place. Two have moved: [P2-2](#p2-2--the-windows-jira-export-drops-the-base-urls-context-path-fixed-by-1245) was fixed by #1245, and [P2-6](#p2-6--the-local-transcription-server-has-no-admission-control-on-upload-size) was partly fixed by #1239. Everything else was still open at the time of writing.
**Scope:** whole repository — Swift macOS app (`Sources/BugNarrator`, 248 files / 36,455 LOC), tests (`Tests/`, 119 files / 26,323 LOC), Windows port (`windows/`, .NET 8 / WPF), local transcription server (`local-transcription/`, Python), CI/CD (`.github/workflows/`, 5 workflows), release automation (`scripts/`, 19 scripts), docs site (`site/`, Docusaurus).
**Method:** five parallel read-only review passes (Swift security; Swift maintainability + UX; Python transcription server; Windows C# port; CI/CD + scripts + docs site + repo hygiene), plus independent line-by-line re-verification of every P0/P1 claim by the parent agent, plus live read-only GitHub API queries (`gh api`, `gh run list`, `gh release list`).
**Verdict:** **FAIL** — 6 confirmed P1 findings, 8 P2, 11 P3. Nothing found that is an actively exploitable remote compromise; the failures are concentrated in *ungated credential transport*, *ungated local services*, and *release/CI controls that report success without doing the work*. Of the P2s, one (P2-2) has since been fixed; the other seven are open.

> **Status.** This is a point-in-time audit, committed as a reference for follow-up
> work. It is not a product document and describes a snapshot at `c8c0070`; it
> goes stale as the code changes. Findings are **open** until fixed or explicitly
> dismissed — treat this file as the work queue, not as a verdict on the project.
> One redaction was applied before publishing: see [P2-3](#p2-3--docsdistributionmd-publishes-the-notarization-apple-id-and-1password-item-name-against-the-repos-own-rule).

---

## How to read this document

- Every P0–P2 finding below was **independently re-verified** by the parent agent against the source at `c8c0070`. Where a sub-reviewer's claim did not survive re-verification, it was dropped (see [Dropped on re-verification](#dropped-on-re-verification)).
- Each finding carries: evidence with `file:line`, the concrete failure scenario, impact, and a specific fix.
- Findings are ordered by severity, then by blast radius.

---

## P1 — High

### P1-1 · Jira credentials and issue content can leave the machine in cleartext; the guard is a UI warning with no gate

**Area:** macOS app, Jira export
**Evidence**

`Sources/BugNarrator/Services/SettingsStore.swift:619` defines the only plaintext check for Jira:

```swift
/// Warning when the configured Jira base URL would send Basic-auth credentials
/// (email + API token) over plaintext HTTP to a remote host. Loopback/private/
/// `.local` HTTP and remote HTTPS return nil. Reuses the host classifier from
/// the AI base-URL guard (#472).
var jiraBaseURLPlaintextWarning: String? {
```

It has exactly **two** references in `Sources/`:

- `Sources/BugNarrator/Services/SettingsStore.swift:619` — the definition
- `Sources/BugNarrator/Views/Settings/SettingsIntegrationsPanes.swift:226` — a `Label` in the settings pane

(`Tests/BugNarratorTests/SettingsStoreTests.swift:490,494` exercise the computed property, so the behaviour is covered — the gap is that nothing *acts* on it.)

Nothing in the export path consults it. `Sources/BugNarrator/Services/JiraExportProvider+Networking.swift:34-45` builds the request URL with no scheme check:

```swift
func jiraRequestURL(
    baseURL: URL,
    path: String,
    queryItems: [URLQueryItem] = []
) throws -> URL {
    guard var components = URLComponents(
        url: baseURL.appending(path: path),
        resolvingAgainstBaseURL: false
    ) else {
```

**The asymmetry is the defect.** The *AI provider* path hard-gates the identical condition. `aiProviderCompatibilityIssue` is consumed as a blocking gate in at least five places:

- `Sources/BugNarrator/AppState.swift:361` — `needsAPIKeySetup`
- `Sources/BugNarrator/AppState.swift:402` — `startSession()` returns early and opens Settings
- `Sources/BugNarrator/AppState.swift:463` — `stopSession()` preserves a retryable session instead of transcribing
- `Sources/BugNarrator/AppState.swift:651` — retry path throws
- `Sources/BugNarrator/Services/AIProviderSettingsController.swift:28` — `validateConnection()` fails

The AI-provider guard was hardened in response to a real incident (the code comments cite **#953**: "Warning about it was not enough… a credential and audio leak"). The same class of bug was never closed on the Jira side.

**Failure scenario:** a user configures Jira with `http://jira.example.com` (a self-hosted Jira on plain HTTP is common, and the field accepts it). The app sends the account email and API token as HTTP Basic credentials — base64, not encryption — plus the full issue body, over an unencrypted connection to a remote host. The only feedback is a line of orange text in Settings that is not even shown on the export screen.

**Impact:** credential disclosure (Jira account email + API token, which typically grants full issue read/write) and issue-content disclosure, over plaintext, to any host the user points at.

**Fix:** mirror the AI-provider pattern.

1. Add `var jiraBaseURLCompatibilityIssue: String?` to `SettingsStore` that returns a non-nil message for a plaintext remote Jira URL.
2. Consume it in the Jira export path (the equivalent of `IssueExportController.preflight…`) and in `AppState` before an export is allowed to proceed — refuse, with a message that names the fix, rather than warn.
3. Keep `jiraBaseURLPlaintextWarning` for the settings UI, but it must not be the only control.

---

### P1-2 · The local transcription server is an unauthenticated, unbounded HTTP endpoint on loopback

**Area:** `local-transcription/server.py` + both desktop clients
**Evidence**

`local-transcription/server.py` exposes three routes and no authentication, CORS policy, or host allow-list anywhere in the file:

```
129:@app.get("/health")
139:@app.get("/v1/models")
154:@app.post("/v1/audio/transcriptions")
```

A grep for `CORS|middleware|Depends|Security|api_key|Authorization|TrustedHost` across the file returns **no** matching code, at either the reviewed commit or `origin/main` after #1239 landed. (Adding `token` to that pattern does match, but only the Whisper tokenization identifiers `token`/`tokens` at `server.py:423,428,431,432,457` — not an auth token.)

At the reviewed commit the upload path also had no size cap (`server.py:170-176`):

```python
    suffix = Path(file.filename).suffix if file.filename else ".m4a"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        contents = await file.read()
        tmp.write(contents)
        tmp.flush()
        tmp.close()
```

`await file.read()` buffered the entire body into memory with no limit and no `Content-Length` pre-check. #1239 (`b30a04e`) has since made the upload **streaming**, so peak memory is bounded — but it added **no total-size cap**, and the endpoint is still unauthenticated. See [P2-6](#p2-6--the-local-transcription-server-has-no-admission-control-on-upload-size).

The client side confirms there is nothing to enforce. `Sources/BugNarrator/Services/TranscriptionClient.swift` and `LocalTranscriptionManager.swift` contain no auth header, token, or shared secret on the local-server path. The health probe accepts *any* responder:

`Sources/BugNarrator/Services/SettingsStore.swift:540-548`

```swift
    static func isHealthyLocalProvider(data: Data?, response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let data,
              let health = try? JSONDecoder().decode(LocalProviderHealth.self, from: data) else {
            return false
        }
        return health.status == "ok"
    }
```

Note `LocalProviderHealth` decodes `model_loaded` at line 552 and **never reads it** — the field is parsed and discarded, so a stub server that answers `{"status":"ok"}` is accepted as a healthy Parakeet server.

**Failure scenario:** any process running on the machine can `POST` audio to `127.0.0.1:8422/v1/audio/transcriptions` and drive the Whisper/Parakeet model — unbounded, unauthenticated, and un-metered. Because there is no auth token at all, there is nothing for the client to present and nothing for the server to check. A rogue local listener that binds port 8422 *before* the app starts its own server also satisfies the health check above (which ignores `model_loaded`) and receives the user's microphone audio.

**Impact:** resource exhaustion (CPU/GPU/bandwidth denial of service against a machine the user is testing on) and, in the port-squatter case, audio disclosure to an unverified local endpoint. The `model_loaded` field being decoded-then-ignored is what makes the second case pass silently.

**Fix**

1. Generate a random token at server start (`secrets.token_urlsafe(32)`), pass it to the client via the launch arguments (the app already spawns the server — `LocalTranscriptionManager.swift:435`), and require it as `Authorization: Bearer <token>` on all three routes. The server prints the token to stdout; the app reads it from the child's stdout.
2. Require the token on `/health` too, and have the client verify `model_loaded == true` — not just `status == "ok"`.
3. Add a hard upload cap: reject on `Content-Length` above a limit (the Swift client already chunks long recordings, so pick a cap comfortably above one chunk) and stream to the temp file instead of `await file.read()`.

---

### P1-3 · The Windows port stores session bodies in plaintext, contradicting the repository's published encryption contract

**Area:** Windows port vs `SECURITY.md`
**Evidence**

`SECURITY.md:43-59` states the at-rest posture as a product-wide table (the two `yes` rows quoted; the four `no` rows — screenshots, preserved audio, telemetry, launch state — are elided):

```markdown
## At-Rest Encryption And Recoverability

Encryption at rest is **partial, and deliberately so**. Exactly this is
encrypted, and nothing else:

| File | Encrypted | Contents |
|---|---|---|
| `Sessions/<id>.json` | **yes** | transcript, summary, markers, extracted issues |
| `sessions.index.json` (+ backup) | **yes** | full-transcript search text, titles, previews |
| … | no | (four further rows, all unencrypted) |

Session bodies and the index are AES-GCM encrypted with a key held in the login
Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
```

The macOS implementation matches. `Sources/BugNarrator/Services/SessionDataProtector.swift:38`:

```swift
let sealedBox = try AES.GCM.seal(data, using: symmetricKey())
```

The Windows implementation does not. The **only** cryptography anywhere in `windows/src` is DPAPI, and it protects secrets, not sessions:

```
windows/src/BugNarrator.Windows.Services/Secrets/DpapiSecretStore.cs:42:  var unprotectedBytes = ProtectedData.Unprotect(
windows/src/BugNarrator.Windows.Services/Secrets/DpapiSecretStore.cs:73:  var protectedBytes = ProtectedData.Protect(
```

There is no `AesGcm`, no `Aes.*`, no `Encrypt`/`Decrypt` for session data in the Windows tree.

Neither disclosure exists. `docs/security/security.md:50` says only:

> Windows release and runtime security posture has not yet been validated on Windows hardware

and `docs/architecture/parity-matrix.md` has no row covering at-rest encryption scope.

**Failure scenario:** a Windows user reads `SECURITY.md` (or the app's own Settings copy) and believes their transcripts and extracted issues are encrypted at rest. They are plain JSON on disk. On a shared or backed-up Windows machine, the session library is readable by anything with file access.

**Impact:** confidentiality expectation is wrong on one of two platforms. The doc explicitly names the threat model ("the derived text is protected from casual file-level access; the source media is not") — on Windows today the derived text is not protected either.

**Fix** — pick one and make it explicit:
- **Port the protection:** implement AES-GCM session storage in `BugNarrator.Core`/`BugNarrator.Windows.Services` with a DPAPI-wrapped key (DPAPI `CurrentUser` scope), matching `SessionDataProtector`. This preserves the documented contract across platforms. **Preferred** — the macOS implementation is small and portable.
- **Or amend the contract:** scope `SECURITY.md` and `docs/security/security.md` explicitly to macOS, state that the Windows port stores sessions in plaintext, and add a parity-matrix row so the difference is tracked rather than implied.

Either way, add the parity row — the matrix currently tracks 25 other contracts but not this one.

---

### P1-4 · `validate.sh` reports "PASS" for Semgrep while scanning zero files

**Area:** mandatory pre-push / pre-merge validation gate
**Evidence**

`scripts/validate.sh:74-82` builds the scan target list:

```bash
SEMGREP_TARGETS=()
if [[ -n "$BASE_REF" ]]; then
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    [[ -f "$target" ]] || continue
    should_skip_semgrep_target "$target" && continue
    SEMGREP_TARGETS+=("$target")
  done < <(git diff --name-only "${BASE_REF}...HEAD" --)
fi
```

The `git diff` runs inside a **process substitution**, so its exit status is discarded by the shell — the `while` loop simply reads whatever stdout it produced.

`scripts/validate.sh:114-115` then treats an empty list as a pass:

```bash
if [[ ${#SEMGREP_TARGETS[@]} -eq 0 && -n "$BASE_REF" ]]; then
  printf 'PASS: no scannable changed files for semgrep\n' | tee "$SEMGREP_STATUS_FILE"
```

**Reproduced locally** (read-only):

```
fatal: bad revision 'bogus-nonexistent-ref...HEAD'
git diff exit code was: 0 (discarded by process substitution)
SEMGREP_TARGETS count: 0
PASS: no scannable changed files for semgrep   <-- validate.sh verdict
```

**Failure scenario:** `AGENTS.md:42` makes `./scripts/validate.sh origin/main` the required validation before pushing. Whenever the base ref is stale, missing, or unrelated — a shallow clone, a renamed `main`, a fetch that never ran, a typo — `git diff` fails, the target list is empty, and `validate.sh` prints a green **PASS** for Semgrep and exits 0. The developer believes the security scanner ran. It did not.

**Impact:** a false-green mandatory gate. This is the single highest-value finding in the CI area because the gate is the process's primary defence and it fails open on exactly the inputs most likely in a fresh or broken checkout.

**Fix**

```bash
changed=""
if ! changed="$(git diff --name-only "${BASE_REF}...HEAD" -- 2>&1)"; then
  printf 'FAIL: could not diff against %s: %s\n' "$BASE_REF" "$changed" >&2
  exit 1
fi
if [[ -z "$changed" ]]; then
  printf 'PASS: no changed files against %s\n' "$BASE_REF" | tee "$SEMGREP_STATUS_FILE"
else
  while IFS= read -r target; do ... done <<<"$changed"
fi
```

Distinguish "no changed files" (genuine pass) from "diff failed" (fail closed). Audit the other process substitutions in `validate.sh` for the same pattern — the shell and Python target lists at lines 238-240 and 259-261 use the same idiom.

---

### P1-5 · Code scanning has been disabled for five months; nothing has scanned since 2026-08-26

**Area:** CI/CD
**Evidence**

`.github/workflows/codeql.yml:11-13` declares a weekly and monthly schedule:

```yaml
  schedule:
    - cron: '0 4 * * 1'  # Weekly on Monday at 4 AM UTC
    - cron: '0 5 1 * *'  # Monthly on the 1st at 5 AM UTC — includes Swift
```

`AGENTS.md:52` states "CodeQL runs on a schedule only." The GitHub API says otherwise:

```
$ gh api repos/ABD-Enterprises/bug-narrator/actions/workflows/259967316
{"name":"CodeQL","state":"disabled_manually","updated_at":"2026-05-27T08:44:57.000-04:00"}
```

GitHub's separate default CodeQL workflow (id `246559978`) last ran **2026-08-26** — and the repository recorded **1,215** workflow runs between 2026-08-27 and this review (a count that keeps growing):

```
$ gh api "repos/ABD-Enterprises/bug-narrator/actions/runs?created=>2026-08-27&per_page=1" --jq .total_count
1215
```

Meanwhile `docs/release/release-process.md:95` and `docs/operations/deployment.md:22` still instruct maintainers to review CodeQL alerts before releasing.

**Failure scenario:** Swift (248 files), Python, C# and JS/TS have had no static security analysis for roughly two months — and the repo's own schedule-driven workflow has been off for five. The documented release step ("review CodeQL alerts") can no longer produce any *new* alerts, so it is a step that always passes without checking anything. The last run left 18 alerts on record, all since closed — the scanner was finding things before it was switched off.

**Impact:** a large, entirely unmonitored static-analysis surface across four languages, combined with a release checklist that references a tool nobody is running.

**Fix:** re-enable `.github/workflows/codeql.yml` (or delete it and rely on default setup), confirm an analysis run completes, and check the alert list before the next release. Then confirm `docs/release/release-process.md` and `docs/operations/deployment.md` describe the workflow that is actually active.

---

### P1-6 · The signing release workflows have no environment gate, no ref constraint, and no tag-namespace validation

**Area:** release automation
**Evidence**

`windows-tester-release.yml` has a `release-preflight` job, but it validates **only** that the signing secrets exist:

`.github/workflows/windows-tester-release.yml:30-48`

```yaml
  release-preflight:
    runs-on: ubuntu-latest
    steps:
      - name: Confirm signing secrets exist before reserving Windows runner
        env:
          CERT_BASE64: ${{ secrets.BUGNARRATOR_WINDOWS_CERT_BASE64 }}
          CERT_PASSWORD: ${{ secrets.BUGNARRATOR_WINDOWS_CERT_PASSWORD }}
        run: |
          missing=()
          if [[ -z "$CERT_BASE64" ]]; then
            missing+=("BUGNARRATOR_WINDOWS_CERT_BASE64")
          fi
```

The release job (`:50-52`) declares **no `environment:`**, and the `gh release create` call (`:104-120`) passes **no `--target`**:

```powershell
          $args = @(
            "release", "create", "$env:RELEASE_TAG",
            "windows/artifacts/packages/BugNarrator-windows-$env:RELEASE_RUNTIME.zip",
            ...
          )
```

`grep -n "environment:"` across the three dispatchable workflows returns exactly one hit — `docs-site.yml:66`. Neither signing workflow has one, and neither constrains `github.ref`.

**The sibling workflow demonstrates the intended standard.** `.github/workflows/local-transcription-windows.yml:58-63`:

```yaml
      - name: Confirm the tag is in the server release namespace
        run: |
          # Only this workflow's own tags may be created or have assets replaced; an app or
          # tester release tag must never be touched from here.
          if [[ ! "$RELEASE_TAG" =~ ^transcription-windows-v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]]; then
            printf '::error::Release tag "%s" is not in the transcription-windows-v<semver> namespace.\n' "$RELEASE_TAG"
            exit 1
          fi
```

and `:220-222` passes `--target "$GITHUB_SHA"` so the release is pinned to the exact reviewed commit.

**Failure scenario:** the guardrails in `AGENTS.md:50-52` ("Publishing is the owner's step", "owner-dispatched") are enforced only by GitHub's dispatch permissions, not by the workflow itself. Any actor with write access — including a hijacked maintainer session — can dispatch `windows-tester-release.yml` from a feature branch. The workflow builds that branch's code, Authenticode-signs it with the repository signing certificate, and publishes it as a GitHub Release with `contents: write`. Because there is no `--target`, the release tag may not point at the commit that was reviewed. With no tag-namespace regex, the same dispatch can also create a release tagged `v1.1.0` or `transcription-windows-v1.0.0`, colliding with the other workflows' namespaces (see P2-1 for the downstream consequence).

**Impact:** a signed, published artifact built from unreviewed code — the exact outcome the repo's release rules exist to prevent.

**Fix**

1. Add `environment:` with required reviewers to both signing release jobs.
2. Gate on `github.ref == 'refs/heads/main'` or on the dispatched ref being an existing release tag.
3. Add the same tag-namespace regex the sibling workflow already uses.
4. Add `--target "$GITHUB_SHA"` to the `gh release create` call.
5. Move `permissions: contents: write` from workflow scope down to the release job so `release-preflight` does not carry it.

---

## P2 — Medium

### P2-1 · "Check for Updates" breaks for every user as soon as any non-app GitHub Release is published

**Area:** macOS + Windows update checks
**Evidence**

Both ports read GitHub's `releases/latest` endpoint and then check only whether the **tag parses as a version**:

`Sources/BugNarrator/Services/ReleaseUpdateCheck.swift` — `GitHubLatestReleaseFeed` fetches `/releases/latest`; `ReleaseVersion.Parse` returns `nil` for any tag that does not begin with a numeric version.

`windows/src/BugNarrator.Windows.Services/Shell/ReleaseUpdateChecker.cs:251-255` — the same logic, same failure mode.

**The fix already exists elsewhere in the codebase.** The transcription-server discovery path filters correctly — `Sources/BugNarrator/Services/LocalTranscriptionManager.swift` selects a release by **asset name** (`bugnarrator-transcription-macos-arm64.dmg`), requires `!draft && !prerelease`, validates the asset URL host and path, and enforces size caps. The update checker does none of that.

**Failure scenario:** `transcription-windows-v1.0.0` and `windows-tester-v0.1.0` are not parseable versions, so `ReleaseVersion.Parse` returns `nil` and `check()` returns `.undetermined(reason: "the latest release tag '…' is not a version")`. The user sees *"BugNarrator could not check for updates"* instead of a real update — including for security fixes, which was the entire point of the update feature. If a tester release were tagged `v1.2.0`, `ReleaseVersion` parses it, and users are told **"BugNarrator 1.2.0 is available"** and sent to a release page containing only Windows tester zips.

GitHub's `releases/latest` returns the most recent **non-draft, non-prerelease** release, so the moment either release workflow is dispatched with `draft: false, prerelease: false`, this fires. Both workflows default to `draft: true` today, so the defect is currently latent — one input away.

Current state is benign: `releases/latest` is `v1.1.0`.

**Impact:** a release-cadence mistake in one workflow silently breaks update delivery for both desktop platforms.

**Fix:** make the update checker filter on asset name the way `LocalTranscriptionManager` already does — require an asset matching `BugNarrator-*-macOS.dmg` (and the equivalent on Windows) before treating a release as an app release. Belt and braces: keep the non-app release workflows on `draft: true`/`prerelease: true`.

---

### P2-2 · The Windows Jira export drops the base URL's context path (fixed by #1245)

**Area:** Windows port
**Status:** **fixed** — see below.
**Evidence**

At the reviewed commit, `windows/src/BugNarrator.Windows.Services/Settings/WindowsAppSettings.cs:258-261` normalized without adding a trailing slash:

```csharp
    public string NormalizedJiraBaseUrl =>
        string.IsNullOrWhiteSpace(JiraBaseUrl)
            ? string.Empty
            : JiraBaseUrl.Trim();
```

`windows/src/BugNarrator.Windows.Services/Export/JiraExportProvider.cs:402` then resolved the path with `AppendPathSegment`, which used `new Uri(baseUri, relativePath)` — RFC 3986 relative resolution, which **replaces** the last path segment rather than appending to it.

Confirmed by RFC 3986 resolution:

```
base='https://jira.example.com/jira'      -> https://jira.example.com/rest/api/3/issue
base='https://jira.example.com/jira/'     -> https://jira.example.com/jira/rest/api/3/issue
base='https://acme.atlassian.net/'        -> https://acme.atlassian.net/rest/api/3/issue
```

macOS got this right — `Sources/BugNarrator/Services/SettingsStore+Normalization.swift:16-21` trims trailing `/` and the URL is built with `appending(path:)`, which appends:

```swift
    var normalizedJiraBaseURL: String {
        jiraBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
```

**Failure scenario:** a user on Jira Server/Data Center configured at `https://jira.example.com/jira` (the standard context-path deployment) exports an issue from Windows. The request goes to `https://jira.example.com/rest/api/3/issue` — the wrong host path, 404, export fails with a confusing error. On macOS the same configuration works.

**Impact:** Jira export is broken on Windows for every context-path Jira Server deployment; works on macOS. A real cross-platform divergence in a shipped feature.

**Fix:** in `WindowsAppSettings.NormalizedJiraBaseUrl`, append a trailing `/` when the URL has a non-empty path (and keep `AppendPathSegment` for the relative path). Add a test that mirrors the macOS normalization test: `https://jira.example.com/jira` → `https://jira.example.com/jira/rest/api/3/issue`.

**Update — fixed by #1245.** `0d078b2` ("fix(windows): preserve Jira export context paths") landed on `main` after this review was written, and fixes exactly this. `AppendPathSegment` now treats the configured path as a directory:

```csharp
    public static Uri AppendPathSegment(this Uri baseUri, string relativePath)
    {
        // Treat the configured context path as a directory, even without a trailing slash.
        var directoryUri = new Uri(baseUri.GetLeftPart(UriPartial.Path).TrimEnd('/') + "/");
        return new Uri(directoryUri, relativePath);
    }
```

It ships with regression tests in `windows/tests/BugNarrator.Windows.Tests/Export/IssueExportProviderTests.cs`. The approach differs slightly from the one this finding suggested (normalising inside `AppendPathSegment` rather than at base-URL normalization); the behaviour is the same, and the fix is the smaller change.

**Nothing further is required for this finding.** It is recorded here for traceability.


---

### P2-3 · `docs/Distribution.md` publishes the notarization Apple ID and 1Password item name, against the repo's own rule

**Area:** documentation hygiene (public repo)
**Evidence**

`docs/Distribution.md:136-145`:

```markdown
- Apple ID: `<personal Apple ID>`
- Team ID: `<team ID>`
- Local keychain profile: `<notary profile name>`
- 1Password item `<password-manager item name>`
- GitHub repository secret `APPLE_APP_SPECIFIC_PASSWORD`
```

> The values are redacted here on purpose. This document is committed to a public
> repository, and `AGENTS.md:39` forbids publishing personal data in it — quoting
> the identifiers verbatim here would publish exactly the leak this finding
> describes. Read the live values at `docs/Distribution.md:136-145`.

`AGENTS.md:54` states: *"Signing and notarization settings (team, notary profile, Apple account) are defaults inside `scripts/build_dmg.sh`; do not copy them into issues, pull requests or docs, and do not change them without the owner."*

`AGENTS.md:39` forbids personal data in this public repository.

**Impact:** the repo violates its own stated rule by publishing the owner's personal email address and the naming of their password-manager item and GitHub secret. Values are not exposed, but the identifiers narrow the target for credential stuffing and social engineering — in a public repository, permanently, in git history.

**Fix:** replace lines 138-145 with placeholders (`<notary Apple ID>`, `<team ID>`, …) and point at `scripts/build_dmg.sh`, which already holds the real defaults. Then rewrite history or accept the address is already public — worth deciding explicitly.

---

### P2-4 · The Screenshots section disappears from the review workspace as soon as issue extraction runs

**Area:** macOS UX
**Evidence**

`Sources/BugNarrator/Views/Transcript/ReviewWorkspaceShell.swift:195-199`:

```swift
            if session.issueExtraction == nil {
                reviewSectionCard("Screenshots") {
                    screenshotsSection()
                }
            }
```

`ScreenshotsSectionContent` has exactly one render site in the codebase — this shell. The live navigation path is `BugNarratorApp.swift:265` → `TranscriptView.swift:241` → `ReviewWorkspaceShell`, so there is no alternate route to the gallery.

**Failure scenario:** a user records a session with eight screenshots, runs issue extraction, and opens the session to review the results. The Screenshots card is gone. The screenshots are reachable only if an individual *extracted issue* happens to reference one. The user's own captured evidence — often the thing they took the screenshots for — silently disappears from the review surface.

**Impact:** a core artifact becomes unreachable through the normal workflow, with no explanation. There is no user-facing signal that the section was conditional.

**Fix:** render the Screenshots card unconditionally. If the intent was to avoid duplicating screenshots already shown inline under an extracted issue, that is a *scoping* decision, not a visibility one — keep the section and mark each screenshot with the issue that references it.

---

### P2-5 · The version-consistency check never runs in CI

**Area:** release hygiene
**Evidence**

`scripts/check_version_consistency.sh` exists and is referenced by `scripts/bump_version.sh:106`, `scripts/release_smoke_test.sh:22`, `AGENTS.md:53` and the contract fixtures — but **not** by `scripts/validate.sh` and **not** by any workflow:

```
$ grep -rn "check_version_consistency" scripts/validate.sh .github/
NOT INVOKED in validate.sh or .github/
```

Both remaining callers are manual, owner-run, release-time scripts.

**Failure scenario:** `VERSION`, `project.yml`'s `MARKETING_VERSION`, and the changelog drift apart during normal development. The drift is not detected until someone runs `bump_version.sh` or `release_smoke_test.sh` at release time — at which point the release is blocked or, worse, ships a version string that does not match the built artifact.

**Impact:** release-time surprise; CI reports green while the version contract is broken.

**Fix:** invoke `scripts/check_version_consistency.sh` from `scripts/validate.sh` (the same way `check-agent-rules-sync.sh` is invoked), so the gate that already runs on every push also checks version consistency.

---

### P2-6 · The local transcription server has no admission control on upload size

**Area:** `local-transcription/server.py`
**Status:** partially fixed after this review — see below.
**Evidence**

At the reviewed commit (`c8c0070`), `local-transcription/server.py:170-176` buffered the full body before any validation:

```python
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        contents = await file.read()
        tmp.write(contents)
```

There was no `Content-Length` check, no streaming, and no cap. (The temp file *was* correctly unlinked in a `finally` block — cleanup was never the problem; admission control was.)

**Update — fixed in part by #1239.** `b30a04e` ("fix(transcription): bound memory on long recordings in the local server", refs #1229) landed on `main` after this review was written. It replaced the single-buffer read with a streamed, piece-wise write:

```python
        # Stream the upload to disk in bounded pieces: a long recording must not be
        # held in memory as one buffer (#1229).
        written = 0
        while True:
            piece = await file.read(_upload_piece_bytes)
            if not piece:
                break
            tmp.write(piece)
            written += len(piece)
```

So the **memory-exhaustion half of this finding is fixed**: peak RSS during an upload is now bounded by `_upload_piece_bytes` (1 MiB) rather than the whole file.

**What still stands.** The fix bounds memory but does not bound *volume*: there is still no `Content-Length` check, no maximum total size, and no early rejection. `grep -nE 'content_length|max_upload|Content-Length'` over `local-transcription/server.py` at `origin/main` returns nothing. The endpoint also remains unauthenticated (P1-2), so nothing gates who may send the body.

**Failure scenario (remaining):** any local process POSTs a multi-terabyte body to the transcription endpoint. The server writes every byte to disk in the temp directory, rejecting nothing, until the volume fills or the request is abandoned. The memory footprint stays flat, which is exactly why this is easy to miss — the symptom moves from RAM to disk.

**Impact:** disk exhaustion on the user's machine from an unauthenticated local endpoint. The memory-pressure variant that made this a P2 at `c8c0070` is gone.

**Fix (remaining):** reject on `Content-Length` above a configured cap (return 413), and enforce the same cap while streaming so a chunked request without a declared length cannot exceed it. The Swift client already chunks long recordings, so size the cap comfortably above one chunk. The shared-secret handshake in P1-2 is the other half — with it, the endpoint is no longer reachable by every local process.

---

### P2-7 · Dead production model with live tests, and an identity function posing as a policy check

**Area:** macOS maintainability
**Evidence**

`ReviewWorkspaceTab` / `availableTabs` / `clampedTab` are defined in `Sources/BugNarrator/Utilities/ReviewWorkspace.swift:4,18` and `Sources/BugNarrator/Utilities/ReviewWorkspaceTypes.swift:3`, but the **only** references anywhere are the definitions and `Tests/BugNarratorTests/ReviewWorkspaceTests.swift`. No production code calls them. The tests are green because they test the dead model directly — they look like coverage of a real feature and provide none.

`Sources/BugNarrator/Utilities/FirstRunFunnel.swift:20`:

```swift
    static func canStartRecording(phaseAllowsStart: Bool) -> Bool {
```

is the identity function, and its two call sites (`Sources/BugNarrator/Views/RecordingControlPanelView.swift:219,221`) pass literal `true` / `false`:

```swift
            return FirstRunFunnel.canStartRecording(phaseAllowsStart: true)
            return FirstRunFunnel.canStartRecording(phaseAllowsStart: false)
```

**Impact:** the codebase carries a decision point that looks like a policy and is not, and a test suite that would keep passing if the tab model were deleted. A maintainer reading `canStartRecording` reasonably assumes a real gate exists there.

**Fix:** delete the `ReviewWorkspaceTab` model, `ReviewWorkspace.swift`, `ReviewWorkspaceTypes.swift`, and `ReviewWorkspaceTests.swift` — or wire the model into the shell if it was meant to drive tab selection. Collapse `canStartRecording` to its single call-site expression, or give it the real predicate it is named for.

---

### P2-8 · The Semgrep Docker image and rule set are unpinned

**Area:** CI supply chain
**Evidence**

`scripts/validate.sh:90-92`:

```bash
  if docker run --rm -v "${ROOT}":/src -w /src -e SEMGREP_APP_TOKEN \
    semgrep/semgrep semgrep scan --config=auto --error "$@" \
```

`semgrep/semgrep` is a mutable tag, and `--config=auto` pulls mutable rules from Semgrep's registry at run time.

**Impact:** an upstream tag move or registry compromise executes in CI. The PR job holds only a read-only token, so the blast radius is CI execution rather than secret theft — but the same `validate.sh` runs locally with `SEMGREP_APP_TOKEN` in the environment, and that token is passed into the container via `-e`.

**Fix:** pin `semgrep/semgrep` by digest (`semgrep/semgrep@sha256:…`) and pin the rule set to a versioned config (`--config=p/default@<version>`), or vendor the config into the repo.

---

## P3 — Low

### P3-1 · Exported session bundles are written world-readable
`Sources/BugNarrator/Utilities/AtomicBundleDirectoryWriter.swift:16,27` calls `createDirectory(at:withIntermediateDirectories: true)` with no `.attributes`, and `Sources/BugNarrator/Services/TranscriptExporter.swift:139-148,157` writes `transcript.md`, `summary.md`, `screenshots/*.png` and `manifest.json` the same way. With the default umask (022) these are `0644` in whatever directory the user picked — typically Desktop or Downloads, where other local users on a shared Mac can read them. (Audio is *not* included in the export — verified against the manifest and exporter.) The in-app library is fine: `~/Library/Application Support` is `0700` by default, and session JSON is AES-GCM encrypted.
**Fix:** create the bundle directory and its files with `posixPermissions: 0o700` / `0o600`.

### P3-2 · `.local` and single-label hostnames are trusted as "local"
`Sources/BugNarrator/Services/SettingsStore.swift:566,568`:
```swift
if lowered.hasSuffix(".local") { return true }
// Single-label hostnames (e.g. "lmstudio") never resolve on public DNS.
if !lowered.contains(".") && !lowered.contains(":") { return true }
```
Apple's `NSAllowsLocalNetworking` documentation confirms ATS provides no protection for unqualified host names or `.local` domains, so plaintext HTTP to `http://attacker.local` is permitted both by the app's classifier *and* by ATS — and an mDNS name can be claimed by any device on the LAN. The API key and transcript would go there in cleartext. A decimal or hex IPv4 literal (`134744072`) also passes line 568, but ATS blocks IP-literal connections by default on macOS 14+ (`project.yml:7` sets `MACOSX_DEPLOYMENT_TARGET: 14.0`), so that vector is neutralised in practice.
**Fix:** restrict the plaintext exemption to genuinely local addresses (loopback / RFC 1918 / link-local) and drop the blanket `.local` and single-label allowances, or require an explicit per-user opt-in for those.

### P3-3 · `actions/checkout` leaves the token in `.git/config` while PR code runs in the same job
Every workflow uses the default `persist-credentials: true` (e.g. `ci.yml:97-144`), so the `GITHUB_TOKEN` sits in the local git config while untrusted PR code executes in that job.
**Fix:** set `persist-credentials: false` on every checkout — the open PR #1228 already does this across the workflows it touches.

### P3-4 · `codeql.yml` adds a `workflow_dispatch` trigger, contradicting `AGENTS.md`
`.github/workflows/codeql.yml:4-10` includes `workflow_dispatch`, while `AGENTS.md:52` states "CodeQL runs on a schedule only."
**Fix:** drop the manual trigger, or amend `AGENTS.md` to document it.

### P3-5 · The fast parse gate only checks `Sources/`
`scripts/swift-parse-check.sh:53` parses `Sources/` only, so a syntax error in `Tests/` passes the local fast gate.
**Fix:** include `Tests/` (and `windows/` is covered by its own build).

### P3-6 · `bump_version.sh` has no dirty-tree guard and is not atomic
`scripts/bump_version.sh:69-77` writes `VERSION` and then `project.yml` before the changelog archive step (`:81-102`), with no `git status` check. A mid-script failure leaves a half-bumped tree.
**Fix:** refuse to run on a dirty tree and write via temp files + rename.

### P3-7 · Windows logs unbounded server response bodies
The Windows HTTP layer reads the entire response body and interpolates it into the error message, so a large or hostile response reaches the log file verbatim — disk-fill and log-injection vector.
**Fix:** cap the body read (e.g. 64 KiB) and truncate before logging.

### P3-8 · The two redactors cover different token shapes
`Sources/BugNarrator/Utilities/DiagnosticsRedactor.swift:22-27` covers `sk-`, `github_pat_`, `gh[pousr]_` and `Bearer`. `windows/src/BugNarrator.Windows.Services/Diagnostics/SensitiveDataRedactor.cs:9-36` covers the same **plus** `Basic` and the Atlassian `ATATT3xFfGF0` prefix. macOS is partly compensated by exact-value redaction of the stored keychain secrets (`sanitizeFreeformText(_:redactingExactValues:)`), but a token pasted into freeform text that is *not* the configured one leaks on macOS and is caught on Windows.
**Fix:** add the `Basic` and `ATATT3xFfGF0` patterns to the macOS redactor.

### P3-9 · The transcription server echoes a client-supplied filename into its logs
`local-transcription/server.py:181-183` (at the reviewed commit; `190-193` after #1239):
```python
        logger.info(
            f"Transcribing {file.filename} ({file_size_mb:.1f} MB) "
```
`file.filename` is attacker-controlled and reaches the log verbatim — CRLF injection into the log stream. (`Path(file.filename).suffix` is safe: `Path`'s suffix is always derived from the final path component, so it cannot contain a separator or escape the temp directory.)
**Fix:** strip control characters from the filename before logging it.

### P3-10 · The local server listens on a fixed port with no token, so it can be squatted
The app starts the server on the default port 8422 and — per P1-2 — the health check accepts any `{"status":"ok"}` responder while ignoring `model_loaded`. A rogue local process that binds 8422 first receives the audio upload. The underlying threat model is weak (such a process already runs as the user and could read the files directly), which is why this is P3 and not P1.
**Fix:** closed by the token + `model_loaded` check in P1-2.

### P3-11 · Cross-port first-run gating semantics have diverged
The Windows port blocks recording until the provider is configured (`windows/src/BugNarrator.Core/Workflow/FirstRunFunnel.cs:48` — `BlocksRecording(step) => step == OnboardingStep.Provider`), while the macOS `canStartRecording` is now an identity function (P2-7). The macOS behaviour moved to the `aiProviderCompatibilityIssue` gate; the Windows port kept a separate mechanism. The parity matrix tracks 25 contracts as "In Progress" but does not track this one.
**Fix:** add a parity-matrix row for first-run recording gating, and reconcile the two implementations.

---

## Verified clean

These were checked specifically and found sound — listed so the next reviewer knows the coverage, not to imply the code is perfect.

**Swift app**
- **Keychain handling.** `Sources/BugNarrator/Services/KeychainSecretStore.swift` holds no state and returns only `OSStatus` codes — the secret value never enters an error message.
- **No secrets in `UserDefaults`.** Settings persist booleans such as `has_openai_key: yes/no`; the API key is never written to preferences.
- **Debug bundle.** `Sources/BugNarrator/Services/DebugBundleExporter.swift` exports `system-info.json`, `app-version.txt`, `macos-version.txt`, `recent-log.txt` and `session-metadata.json` — no key, token, or password field.
- **LLM output → GitHub.** `Sources/BugNarrator/Services/GitHubExportProvider+IssueBody.swift` neutralizes LLM-derived markdown so it cannot create `@mentions`, `#issue` cross-links, raw HTML, or new block-level structure.
- **LLM output → Jira.** Issues are built as ADF plain-text blocks — no markdown rendering surface.
- **Prompt injection from tracker data.** `Sources/BugNarrator/Services/SimilarIssueReviewService.swift:177-210` delimits remote issue text, labels it untrusted, and neutralizes attempts to forge the delimiters (issue #950). This is a mature defence.
- **No command injection.** The `/bin/sh` wrapper in `Sources/BugNarrator/Services/LocalTranscriptionManager.swift:459,462` runs `exec "$@"` with positional parameters — arguments are passed as separate argv entries, never interpolated into the script text.
- **No ATS exceptions** in `Resources/Info.plist` — ATS is on by default.
- **At-rest encryption on macOS.** `Sources/BugNarrator/Services/SessionDataProtector.swift:38` uses `AES.GCM.seal` with a device-scoped Keychain key.
- **Crash safety.** Zero force unwraps, `as!`, `try!`, `fatalError`, `TODO`, `FIXME` and `HACK` in `Sources/BugNarrator/**` — the recent cleanup pass (#1224 era) held.

**Python server**
- **Temp-file cleanup.** The uploaded audio is unlinked in a `finally` block — nothing is left on disk. (The block was refactored to use `contextlib.suppress(OSError)` by #1239; the behaviour is unchanged.)
- **Temp-path safety.** The suffix derived from the client filename cannot contain a separator.
- **Loopback default.** The server binds `127.0.0.1` by default and the app does not pass `--host`.

**Windows port**
- **Authenticode chain is sound.** `AuthenticodeVerifier.cs` runs `WinVerifyTrust` (validating signature *and* file digest, so a post-signing modification fails), then matches the publisher `O=` RDN exactly — never by substring. `LocalServerInstaller.cs:92` verifies the **staged** file before moving it into place, and `LocalTranscriptionServerManager.cs:221` **re-verifies immediately before every launch** ("as macOS re-runs verifyBinary"). The residual TOCTOU is low severity: the install directory is `%LOCALAPPDATA%`, so only same-user code could exploit it, and such code already has full access.
- **JQL is escaped.** Search terms are tokenized before being embedded in JQL.
- **DPAPI scope** is `CurrentUser`.

**CI / repo**
- **`build_dmg.sh` fails closed.** `PUBLIC_RELEASE=YES` refuses unsigned, unnotarized, dirty-tree and untagged builds, and the Developer ID team ID is pinned and compared.
- **No tracked artifacts.** `git ls-files` matches nothing under `local-transcription/venv/`, `dist/`, `artifacts/` or `logs/`; `.gitignore` covers all of them.
- **`.gitleaks.toml` is narrowly scoped** — exactly two commit SHAs, no pattern-level allowlist.
- **Action pinning.** All third-party GitHub Actions are SHA-pinned; no `pull_request_target`; no `curl | bash`; no secret used in an `if:` condition; no PR title, body or branch name interpolated into a `run:` block.
- **The PR path of `local-transcription-windows.yml` really is unsigned and publishes nothing** — signing (`:137,147`) and publish (`:185`) are gated on `github.event_name == 'workflow_dispatch'`; the 2026-10-20 PR run succeeded with no release created, and no `transcription-windows-*` tag exists.
- **Xcode project is in sync** with `project.yml` (all 248 source files referenced, matching version/build settings) with no absolute paths in `project.pbxproj`.
- **Docs site.** Deploys only from `main`; no unsanitized interpolation of repo content into HTML; no leaked host names, customer names or private paths (only the app's own `http://localhost:8422`); `scripts/site_npm.sh` verifies the Node tarball against Node's published SHA-256 before extraction.

---

## Dropped on re-verification

Recorded so a future reviewer does not re-investigate them.

- **"Authenticode verification is bypassable" (Windows).** The implementation is correct: `WinVerifyTrust` validates the digest and the publisher match is an exact RDN comparison. The verify-then-execute window is real but requires same-user code, which has equivalent access already. Retained only as a P3 note under P3-10's neighbourhood — not reported as a vulnerability.
- **"The merge_group CI path fails."** `git fetch origin ""` was tested against a real remote and exits 0 (git resolves the empty refspec to `HEAD`). No finding.
- **"CI has not run since 2026-09-28."** Stale claim from open PR #1228. The API shows 1,215 workflow runs since 2026-08-27, with today's CI runs green. CI is healthy; the real gap is CodeQL (P1-5).
- **"The update checker fails on any non-app release."** Retained as P2-1, but downgraded from "breaks today" — both release workflows currently default to `draft: true`, so the defect is latent rather than active.
- **"Session screenshots are world-readable in the app library."** `~/Library/Application Support` is `0700` by default, so the in-app library is protected. Only *exported* bundles are affected (P3-1).

---

## Coverage and limitations

**Covered:** Swift app security and maintainability; Swift UI/UX; the Python transcription server end to end; the Windows C# port; all five GitHub Actions workflows; all 19 scripts in `scripts/`; the docs site; repository hygiene; live GitHub API state for workflows, runs, releases and code scanning.

**Not covered / limitations**
- **The Windows port was not compiled or tested.** This review ran on macOS, and `docs/architecture/parity-matrix.md` records all 25 Windows contracts as "In Progress", blocked on real-desktop validation (#1133). Every Windows finding here is **static analysis only**.
- **The Python server was not executed.** Its findings are from reading the source; the unbounded-upload and no-auth claims were confirmed by reading, not by sending traffic.
- **The Swift app was not run.** No build, no test execution, no interaction with the real keychain or real session data.
- **Branch protection / ruleset state** was read on 2026-10-21 per `AGENTS.md` and was not independently re-verified here. The `required-checks` list should be confirmed against the workflow job names actually in use, since `ci.yml` defines the checks by job name.
- **Dependency vulnerabilities** were reviewed for pinning and for the known advisories the repo has already fixed (`certifi`, `tinypool`, `follow-redirects`, `launch-editor`), but no fresh advisory database scan was run against every transitive package.
- **The Swift security sub-review** did not file a written report before it was stopped; its three leading findings — the Jira plaintext gate asymmetry, the host-classifier bypass, and export-bundle permissions — were independently re-verified above and are reported on their own merits.

---

## Suggested sequencing

| # | Finding | Effort | Why first |
|---|---|---|---|
| 1 | P1-4 Semgrep false-green | ~15 min | A failing gate is worse than a missing one; this one is the process's spine. |
| 2 | P1-5 CodeQL re-enable | ~30 min + first run | Two months of unscanned code across four languages; the fix is a toggle. |
| 3 | P2-3 Redact the Apple ID from `docs/Distribution.md` | ~5 min | Public repository, personal identifier, own rule already says not to. |
| 4 | P1-1 Jira plaintext gate | ~1 h | Credential disclosure path, and the fix pattern already exists in-repo. |
| 5 | P2-5 Version consistency into CI | ~15 min | One line in `validate.sh`. |
| 6 | P1-2 Local server auth | ~1 day | Needs a token handshake on both sides, plus the total-size cap that #1239 left open (P2-6). |
| 7 | P1-3 Windows at-rest parity | ~2-3 days | The largest single piece of work; decide port-vs-document first. |
| 8 | P1-6 Release workflow guards | ~1 h | Environment, ref constraint, namespace regex, `--target`. |
| 9 | P2-1 Update checker asset filter | ~1 h | Mirrors logic that already exists in `LocalTranscriptionManager`. |
| 10 | ~~P2-2 Windows Jira context path~~ | — | **Done** — fixed by #1245 (`0d078b2`) with regression tests. |
| 11 | P2-4 Screenshots section | ~30 min | User-visible regression, one `if`. |
| 12 | P2-7 Dead model + identity function | ~30 min | Pure deletion; removes a misleading decision point. |
