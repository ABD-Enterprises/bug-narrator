# BugNarrator docs site

A [Docusaurus](https://docusaurus.io) site. Its pages under `docs/` are
mirrors of canonical files in the repository root's `docs/`; `scripts/validate.sh`
fails if they drift, so edit the canonical file and let the sync regenerate the
mirror rather than editing here.

## Building locally

Use the wrapper instead of a globally installed `npm`:

```bash
scripts/site_npm.sh ci        # install dependencies from package-lock.json
scripts/site_npm.sh run build # production build into site/build
scripts/site_npm.sh start     # dev server with live reload
```

`scripts/site_npm.sh` is `npm --prefix site` with a pinned toolchain in front of
it. On first use it:

1. reads the exact Node version from [`.node-version`](.node-version)
   (currently `v22.22.2`),
2. downloads that release for your platform (macOS or Linux, x64 or arm64) from
   `nodejs.org/dist`,
3. verifies the archive's SHA-256 against the release's published
   `SHASUMS256.txt` and refuses to extract on a mismatch,
4. installs it under `build/tooling/node-<version>-<platform>/` (gitignored),

and then `exec`s that toolchain's `npm` with your arguments. Later runs skip the
download. Delete the `build/tooling` directory to force a fresh install.
`SITE_DIR` and `NODE_VERSION_FILE` can be overridden in the environment for
out-of-tree builds.

## What CI uses

The `docs-site-validation` job in `.github/workflows/ci.yml` runs
`npm ci --prefix site` and `npm run build --prefix site` on a Node provided by
`actions/setup-node` with `node-version: 22`. That is a **major-version** pin,
not `node-version-file`, so CI may build on a different `22.x` patch release
than the one `.node-version` pins for local builds. Treat `.node-version` as the
reference: when you bump it, check that CI is still on the same major line.
