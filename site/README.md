# BugNarrator docs site

A [Docusaurus](https://docusaurus.io) site. One page,
`docs/user/user-manual.md`, is a generated mirror of the repository root's
`docs/user/user-manual.md` (see `scripts/sync_site_docs.py`); `scripts/validate.sh`
and the publish workflow fail if it drifts, so edit the canonical file and run
`scripts/sync_site_docs.py` to regenerate the mirror. The other pages are
hand-written summaries that link back to the canonical repo docs.

## Building locally

Use the wrapper instead of a globally installed `npm`:

```bash
scripts/site_npm.sh ci        # install dependencies from package-lock.json
scripts/site_npm.sh run build # production build into site/build
scripts/site_npm.sh start     # dev server with live reload
```

`scripts/site_npm.sh` is `npm --prefix site` with a pinned toolchain in front of
it. Every run reads the exact Node version from
[`.node-version`](.node-version) (currently `v22.22.2`). If that toolchain is
not installed yet, it:

1. downloads that release for your platform (macOS or Linux, x64 or arm64) from
   `nodejs.org/dist`,
2. verifies the archive's SHA-256 against the release's published
   `SHASUMS256.txt` and refuses to extract on a mismatch,
3. installs it under `build/tooling/node-<version>-<platform>/` (gitignored),

and then `exec`s that toolchain's `npm` with your arguments. Later runs skip the
download. Delete the `build/tooling` directory to force a fresh install.
`SITE_DIR` and `NODE_VERSION_FILE` can be overridden in the environment for
out-of-tree builds.

## What CI uses

Two workflows build the site, and they pin Node differently:

- **PR gate** — the `docs-site-validation` job in `.github/workflows/ci.yml`
  (runs only when docs changed) does `npm ci --prefix site` and
  `npm run build --prefix site` on `actions/setup-node` with `node-version: 22`.
  That is a **major-version** pin, so this job may build on a different `22.x`
  patch release than `.node-version`.
- **Publish** — `.github/workflows/docs-site.yml` (push to `main`) uses
  `node-version-file: site/.node-version`, the same exact pin as the local
  wrapper, and also runs the mirror check.

Treat `.node-version` as the reference: when you bump it, check that the PR
gate is still on the same major line.
