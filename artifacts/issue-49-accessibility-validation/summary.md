# Issue 49 Accessibility Validation Summary

Date: 2026-05-12

GitHub issue: https://github.com/deffenda/bug-narrator/issues/49

## Runtime Assistive-Technology Pass

Runtime validation used the macOS Accessibility API against a current Debug release-candidate build launched with deterministic safe UI-test services. The same AX tree is the app surface consumed by assistive technologies such as VoiceOver.

Captured artifacts:

- `ax-settings-runtime.txt`
  - passed required text checks for `BugNarrator Settings`, `AI provider`, `OpenAI API Key`, `AI provider base URL`, `Recording audio source`, `Settings scroll area`, `AI provider status`, `GitHub export status`, and `Jira export status`
- `ax-recording-controls-runtime.txt`
  - passed required text checks for `Recording controls dialog`, `Recording status`, `Start Recording`, `Capture Screenshot`, and `Close`
- `ax-session-library-runtime.txt`
  - passed required text checks for `Session filters`, `Session list`, `Session detail`, `Search sessions`, and `All Sessions`

The reusable helper for this pass is `scripts/assistive_technology_ax_snapshot.swift`.

The focused XCTest UI command for the settings status rows was also attempted, but the local runner timed out while enabling XCTest automation mode. The runtime AX snapshots above launched the app directly and completed successfully.

## Published Docs-Site Pass

Published site checked:

```bash
npx --yes lighthouse@12.8.2 https://deffenda.github.io/bug-narrator/ --only-categories=accessibility --chrome-flags='--headless=new --no-sandbox' --output=json --output-path=artifacts/issue-49-accessibility-validation/lighthouse-published-docs.json
```

Result:

- accessibility score: 96
- failed audit: `color-contrast`
- affected selector: `nav.theme-doc-breadcrumbs > ul.breadcrumbs > li.breadcrumbs__item > span.breadcrumbs__link`
- root cause: the Docusaurus primary link color `#126de6` produced a 4.3:1 contrast ratio on `#f2f2f2`, below the required 4.5:1 ratio

Fix:

- darkened the site primary color tokens in `site/src/css/custom.css`

Local fixed site checked:

```bash
npm run build --prefix site
npm run serve --prefix site -- --host 127.0.0.1 --port 4173
npx --yes lighthouse@12.8.2 http://127.0.0.1:4173/bug-narrator/ --only-categories=accessibility --chrome-flags='--headless=new --no-sandbox' --output=json --output-path=artifacts/issue-49-accessibility-validation/lighthouse-local-docs-fixed.json
```

Result:

- accessibility score: 100
- failed audits: none

## Static Regression Check

`./scripts/accessibility_regression_check.sh` passed after updating the settings checks to match the current AI-provider labels.
