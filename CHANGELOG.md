# Changelog

## Unreleased

- [FIX] Windows recording controls show saved recordings that still need transcription, offer Retry Transcription and Open Settings, and restore recovery after reopening the controls. Retry uses the same saved-session service as the library and refuses duplicate requests for the same session.

- [FIX] Local transcription bounds its memory on long recordings (#1229): uploads are streamed to disk in 1 MB pieces instead of read whole, each backend decodes one 120 s window at a time (ffmpeg seek windows on macOS, windowed WAV reads elsewhere), and the MLX Metal cache is released after every window and when a job finishes or fails, so peak resident memory no longer grows with recording length.
- [INTERNAL] Agent files follow the fleet standard: `AGENTS.md` is the single copy of the agent rules, `CLAUDE.md` only imports it and `.agent/rules.md` points at it; `scripts/check-agent-rules-sync.sh` now checks that layout instead of identical bodies, and the old ORC adapter text is gone.
- [SECURITY] The local transcription server's hash-locked builds (standalone, Windows x64 and Windows ARM64) move `certifi` from 2026.7.22 to 2026.10.19, which drops the emSign root CAs whose intermediate CA keys were compromised (GHSA-6q48-6c7w-9gw2, CWE-295, critical); no other pin changes.
- [SECURITY] The docs site (`/site`) dependency tree is updated to patched versions of `proxy-addr`, `shell-quote`, `compression`, `webpack-dev-middleware`, `http-cache-semantics`, `postcss-selector-parser`, `serialize-javascript`, `sirv` and `source-map-js`; `npm audit` for the site drops from 47 to 29 vulnerabilities (the rest need a Docusaurus migration or have no upstream fix).
- [SECURITY] The docs site (`/site`) now resolves `tinypool` 2.2.0 (root npm override; was 1.1.1, which carries a critical advisory); its only call site is Docusaurus's SSG worker pool behind `future.faster.ssgWorkerThreads`, which the site does not enable, and the site build is unchanged.
- [FIX] Audio recording: guarantee probe cleanup and reset active recording state on failed start, stop, or cancel to prevent temporary file leaks and zombie session locks.
- [SECURITY] The docs site (`/site`) no longer ships a vulnerable `brace-expansion`: a stale npm override pinned 1.1.18, which three newer advisories (high) affect; it now pins 1.1.21, and `fast-uri` moves to 3.1.8. `npm audit` for the site reports 0 vulnerabilities.
- [INTERNAL] Removed the unused Gemini Code Assist GitHub App configuration files.
- [INTERNAL] Removed the empty Terraform placeholder directory (no resources, providers or modules) and the docs and `.gitignore` entries that referred to it.
- [INTERNAL] Dependabot now also covers npm (`/site`) and pip (`/local-transcription`), monthly and grouped with a 7-day cooldown and semver-major held for review.
- A long recording with a silent stretch now transcribes: an empty chunk is skipped instead of failing the whole transcription (and every retry).
- Windows: recordings longer than about 13 minutes now transcribe — the WAV is uploaded in 8-minute chunks instead of failing at the provider's 25 MB limit after the upload.
- Windows: an issue whose primary field is null but carries an alias (e.g. `"title": null, "issueTitle": …`) or whose primary field is the wrong kind (`"confidence": "high"` beside `"score"`) is now read like macOS reads it, instead of failing the whole extraction or losing the field.
- Windows: untrusted text in exported GitHub issues can no longer render masked links, images, indented headings or forged list items (the macOS hardening, ported), and issue titles are normalised to one line and capped at Jira (255) / GitHub (256) limits before export.
- Windows session summaries no longer cut the lead sentence at a decimal point or a dot inside a word ("Version 1.2 crashed" summarised as "Version 1.").
- Windows: a model reply carrying a non-finite timestamp or confidence ("NaN", "1e999") no longer crashes the session library; such values are treated as absent, and time labels render 0:00 for any non-finite value already saved.
- Windows screenshot geometry can map a selection piecewise into each monitor's native pixels (groundwork for per-monitor DPI capture; behaviour unchanged until the PerMonitorV2 switch in #1192).
