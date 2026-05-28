#!/usr/bin/env bash
# Detect GitHub issue/PR states that waste agent or CI effort.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="${EFFORT_LEAK_REPO:-}"
if [[ -z "$REPO" ]]; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    git@github.com:*)
      REPO="${origin_url#git@github.com:}"
      REPO="${REPO%.git}"
      ;;
    https://github.com/*)
      REPO="${origin_url#https://github.com/}"
      REPO="${REPO%.git}"
      ;;
  esac
fi

if [[ -z "$REPO" ]]; then
  echo "NOT RUN: could not infer GitHub repo from origin remote."
  exit 0
fi

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

issues_json="$(mktemp)"
prs_json="$(mktemp)"
audit_output="$(mktemp)"
trap 'rm -f "$issues_json" "$prs_json" "$audit_output"' EXIT

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
  --json number,title,labels,url,closingIssuesReferences \
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
      | select(((.closingIssuesReferences // []) | length) == 0 and (has_label("chore:trivial") | not))
      | "PR #\(.number) has no linked closing issue and is not labeled chore:trivial."
    ] as $findings |
    if ($findings | length) == 0 then
      "PASS: no effort-leak issue/PR states detected."
    else
      $findings[]
    end |
    if type == "string" then . else empty end
  ' | tee "$audit_output"

if grep -qv '^PASS:' "$audit_output"; then
  exit 1
fi
