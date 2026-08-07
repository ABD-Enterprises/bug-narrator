# Contributing

BugNarrator is not currently accepting outside code contributions or pull requests.

## What Is Welcome

- bug reports through [GitHub Issues](https://github.com/ABD-Enterprises/bug-narrator/issues/new)
- focused feature requests through [GitHub Issues](https://github.com/ABD-Enterprises/bug-narrator/issues/new)
- reproducible diagnostics such as debug bundles, session bundles, and screenshots when relevant

## Current Policy

- please do not open pull requests for BugNarrator at this time
- GitHub issues are the right place for bug reports and product feedback
- if contribution policy changes later, this document will be updated

## Validation Evidence

Local run output — `scripts/validate.sh` status files, `xcodebuild` test logs,
release smoke logs, accessibility snapshots — is written under `artifacts/`,
which is gitignored. Do not commit it.

Evidence belongs where it can be read in context:

- paste or attach it to the issue or pull request it justifies
- upload it as a CI artifact when a workflow produced it
- attach release evidence to the corresponding GitHub Release

These files are never edited after they are written, so committing them only
bloats clones and normalizes checking in scratch output.
