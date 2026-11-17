# Contributing

## How to contribute

Issues and pull requests are both welcome. For anything larger than a small fix,
open or comment on an issue first so we agree on the approach.

Sign off every commit with `git commit -s`. This adds a `Signed-off-by:` line
certifying the [Developer Certificate of Origin](https://developercertificate.org/):
you wrote the change or have the right to submit it under the licence in this
repository's `LICENSE` file, and your contribution comes under that licence. A
check confirms the sign-off on pull requests from outside contributors. Every
pull request gets review and must pass the required checks before a maintainer
merges it.

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
