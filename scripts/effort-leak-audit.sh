#!/usr/bin/env bash
# Detect GitHub issue/PR states that waste agent or CI effort.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "NOT RUN: gh is not available."
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "NOT RUN: gh is not authenticated."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "NOT RUN: jq is not available."
  exit 0
fi

REPO="${EFFORT_LEAK_REPO:-}"
if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

if [[ -z "$REPO" ]]; then
  echo "NOT RUN: could not infer GitHub repo."
  exit 0
fi

issues_json="$(mktemp)"
prs_json="$(mktemp)"
audit_output="$(mktemp)"
trap 'rm -f "${issues_json:-}" "${prs_json:-}" "${audit_output:-}"' EXIT

gh issue list \
  --repo "$REPO" \
  --state open \
  --limit 200 \
  --json number,title,labels,url \
  >"$issues_json"

gh pr list \
  --repo "$REPO" \
  --state open \
  --limit 200 \
  --json number,title,labels,url,closingIssuesReferences,author,body \
  >"$prs_json"

jq -r -e -n \
  --slurpfile issues "$issues_json" \
  --slurpfile prs "$prs_json" '
    def labels: [.labels[].name];
    def has_label($name): labels | index($name) != null;
    def active_ai:
      has_label("ai/ready-for-work") or
      has_label("ai/in-development") or
      has_label("ai/in-local-testing") or
      has_label("ai/in-pr-review") or
      has_label("ai/ready-for-local-testing");

    ($issues[0] // []) as $issues_list |
    ($prs[0] // []) as $prs_list |
    (
      [
        $issues_list[]
        | select(has_label("ai/blocked") and active_ai)
        | "Issue #\(.number) is blocked but also carries an active AI workflow label: \([.labels[].name] | join(", "))"
      ] +
      [
        $issues_list[]
        | . as $issue
        | select((has_label("ai/in-pr-review") or has_label("ai/ready-for-local-testing")) and (([ $prs_list[] | select((.closingIssuesReferences // []) | any(.number == $issue.number)) ] | length) == 0))
        | "Issue #\(.number) is in review/testing state but no open PR closes it."
      ] +
      [
        [
          $prs_list[]
          | . as $pr
          | ($pr.closingIssuesReferences // [])[].number
          | {issue: ., pr: $pr.number}
        ]
        | sort_by(.issue)
        | group_by(.issue)[]
        | select(length > 1)
        | "Issue #\(.[0].issue) has multiple open PRs claiming closure: \([.[].pr | "#\(.)"] | join(", "))"
      ] +
      [
        $prs_list[]
        | select(
            ((.closingIssuesReferences // []) | length) == 0 and
            (((.body // "") | test("(?i)\\b(refs|part of)\\s+#[0-9]+")) | not) and
            (has_label("chore:trivial") | not) and
            (((.author.is_bot // false) or ((.author.login // "") | (endswith("[bot]") or . == "dependabot" or . == "app/dependabot"))) | not)
          )
        | "PR #\(.number) has no linked closing issue and is not labeled chore:trivial."
      ]
    ) as $findings |
    if ($findings | length) == 0 then
      "PASS: no effort-leak issue/PR states detected."
    else
      $findings[]
    end |
    if type == "string" then . else empty end
  ' | tee "$audit_output"

# Enforcement is scoped to the PR under test; reporting is not (#941).
#
# The audit deliberately looks at every open PR, because effort leak is a
# repo-wide property. But this script also backs `runtime-guardrails`, a
# REQUIRED per-PR check — so an unrelated non-conforming PR used to turn the
# gate red on every open PR at once, blocking authors on a condition they
# could only fix by editing someone else's PR.
#
# Every finding is still printed above. What changes is which ones fail the
# run: when a PR context is known, only findings naming that PR do.
# Unscoped runs (local, manual, scheduled) keep failing on anything, so
# repo-wide enforcement is not lost — it just moves off the per-PR gate.
scope_pr="${EFFORT_LEAK_PR:-}"
if [[ -z "$scope_pr" && "${GITHUB_REF:-}" =~ ^refs/pull/([0-9]+)/ ]]; then
  scope_pr="${BASH_REMATCH[1]}"
fi

findings="$(grep -v '^PASS:' "$audit_output" || true)"
[[ -z "$findings" ]] && exit 0

if [[ -n "$scope_pr" ]]; then
  # Word-boundary match so #94 does not match #941.
  own_findings="$(printf '%s\n' "$findings" | grep -E "(^|[^0-9])#${scope_pr}([^0-9]|$)" || true)"

  if [[ -z "$own_findings" ]]; then
    echo "::notice::effort-leak: findings exist for other open PRs but none name PR #${scope_pr}; not failing this check. Run the audit unscoped to see them all."
    exit 0
  fi

  echo "::error::effort-leak: PR #${scope_pr} has its own finding(s) above."
  exit 1
fi

exit 1
