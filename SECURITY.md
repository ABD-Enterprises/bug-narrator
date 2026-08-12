# Security Notes

Structured security documentation now lives in [docs/security/security.md](docs/security/security.md).
This top-level note remains the concise repository summary.

BugNarrator is distributed as a local macOS app. Release builds and DMGs should be signed and notarized before public distribution whenever practical.

## Permissions

BugNarrator requests permission only when the related feature is used.

- microphone access is requested when you start recording
- Screen Recording access is requested when you capture a screenshot

BugNarrator does not require Accessibility permission for its core workflow.

## Credentials

BugNarrator uses a bring-your-own-credentials model.

- the app does not ship with a shared OpenAI API key
- the app does not ship with bundled GitHub or Jira credentials
- users provide their own OpenAI, GitHub, and Jira secrets in Settings
- secrets are stored in macOS Keychain when available
- if Keychain storage is unavailable, secrets are kept only in memory for the current run

Do not commit real keys, tokens, or local override files.

## What Is Sent To OpenAI

BugNarrator sends data to OpenAI only when you trigger an OpenAI-backed action.

That includes:

- recorded session audio after you stop a session and request transcription
- transcript context when you request a review summary
- transcript, markers, and screenshot filenames/timestamps when you run issue extraction
- the screenshot images themselves during issue extraction, but only when you enable Settings > Diagnostics & Privacy > "Send screenshots to the AI provider". That setting is off by default; before it existed, up to four screenshots were uploaded unconditionally
- titles and summaries of candidate issues fetched from your GitHub or Jira tracker, when duplicate review runs. That text originates outside BugNarrator, so it is delimited and marked untrusted in the prompt

The app does not stream live dictation into other apps and does not upload audio continuously while you are still recording.

## At-Rest Encryption And Recoverability

Encryption at rest is **partial, and deliberately so**. Exactly this is
encrypted, and nothing else:

| File | Encrypted | Contents |
|---|---|---|
| `Sessions/<id>.json` | **yes** | transcript, summary, markers, extracted issues |
| `sessions.index.json` (+ backup) | **yes** | full-transcript search text, titles, previews |
| `Screenshots/*.png` | no | screen captures you took |
| preserved recording audio | no | the raw session audio |
| `operational-telemetry.jsonl` | no | event names and timestamps, no transcript content |
| `launch-state.json` | no | launch bookkeeping |

Session bodies and the index are AES-GCM encrypted with a key held in the login
Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The key never
leaves the machine and is not included in any export.

**Screenshots and recordings are plaintext on disk.** That is a decision, not
an oversight: screenshots are opened by Finder and Preview from the Reveal in
Finder action and rendered by the thumbnail cache, and preserved audio is
re-read for retry transcription. Encrypting them would break those paths, and a
decrypt-to-temp workaround would put a plaintext copy on disk anyway during use.

So the honest threat model is: **the derived text is protected from casual
file-level access; the source media is not.** Anyone who can read your home
directory can look at your screenshots and listen to your recordings. If that
matters for your work, the control that actually covers it is FileVault, which
encrypts the whole volume including everything above.

The tradeoff is explicit: the encrypted store is **not recoverable on a
different machine**. Restoring the files from Time Machine, migrating with
Migration Assistant, or recovering a disk from a dead Mac all produce a library
that cannot be decrypted, because the key was device-scoped by design.

Use **Settings > Diagnostics & Privacy > Export Data** to produce a
key-independent copy before migrating. That export is plaintext by necessity —
it exists precisely so it does not depend on the device key — so store it with
the same care as the transcripts themselves.

## What Is Sent To GitHub Or Jira

GitHub or Jira data is sent only when you explicitly export selected extracted issues.

That may include:

- issue title
- issue summary
- transcript evidence excerpt
- timestamps
- screenshot filenames and attachment guidance

The app does not silently create remote issues.

## Local Data

BugNarrator stores these items locally on your Mac:

- transcript history
- markers and screenshot metadata inside saved sessions
- captured screenshot files
- exported transcript bundles
- temporary audio files until cleanup

Temporary audio files are removed after success, failure, or cancellation unless `Debug Mode` is enabled.

Release artifacts created locally by the packaging script are written to `dist/` by default and should not be committed to the repository.

## Logging Expectations

BugNarrator should never log:

- OpenAI API keys
- GitHub tokens
- Jira API tokens
- raw Authorization headers

When changing networking code, keep request logging disabled or carefully redacted.

BugNarrator does not include automatic telemetry or background log uploads. Diagnostics stay local unless a user explicitly copies debug info or exports a debug bundle for support.

## Debug Bundle Safety

`Export Debug Bundle` is designed for support without exposing credentials.

The exported debug bundle can include:

- app version and build
- macOS version and architecture
- recent local diagnostics logs
- safe session metadata such as counts, timestamps, and artifact presence

It must not include:

- OpenAI API keys
- GitHub tokens
- Jira tokens
- raw credentials

## Reporting Security Concerns

If you find a security issue, avoid posting secrets or exploit details in a public issue. Report the concern privately to the maintainer first.
