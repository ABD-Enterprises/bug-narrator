# Contributing

## How to contribute

Issues are welcome: bug reports, questions and ideas. Pull requests from
outside contributors are not accepted for now, so that the project keeps a
single copyright holder; a pull request from outside may be closed without
review. Open an issue describing the change instead.

- Open bug reports and feature requests in
  [GitHub Issues](https://github.com/SureForgeTech/sureforge-capture/issues/new).
  Reproducible diagnostics such as debug bundles, session bundles and
  screenshots help when relevant.
- For how to write a good issue, see the
  [SureForgeTech contributing guide](https://github.com/SureForgeTech/.github/blob/main/CONTRIBUTING.md).
- Do not report security problems in a public issue; follow
  [SECURITY.md](SECURITY.md).

## For maintainers: validation evidence

Local run output — `scripts/validate.sh` status files, `xcodebuild` test logs,
release smoke logs, accessibility snapshots — is written under `artifacts/`,
which is gitignored. Do not commit it.

Evidence belongs where it can be read in context:

- paste or attach it to the issue or pull request it justifies
- upload it as a CI artifact when a workflow produced it
- attach release evidence to the corresponding GitHub Release

These files are never edited after they are written, so committing them only
bloats clones and normalizes checking in scratch output.
