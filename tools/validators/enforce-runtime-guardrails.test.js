const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..", "..");
const validatorPath = path.join(repoRoot, "tools", "validators", "enforce-runtime-guardrails.js");

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeText(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, value);
}

function buildFixtureRoot() {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "runtime-guardrails-"));
  const updatedAt = "2026-04-05T07:30:00Z";

  writeJson(path.join(fixtureRoot, "ai.config.json"), {
    run_profile: "standard",
    requires_test_evidence: true,
    requires_deploy_evidence: true,
    allowed_phases_without_tests: ["planning", "docs"],
    strict_mode: true,
    evidence_directories: ["artifacts/"],
    meta_directories: [],
    allowed_metadata_only_evidence_types: ["build", "test", "run", "deploy"],
    protected_environment_paths: ["brew/"]
  });

  writeText(
    path.join(fixtureRoot, ".github", "workflows", "ci.yml"),
    [
      "name: CI",
      "on:",
      "  pull_request:",
      "jobs:",
      "  runtime-guardrails:",
      "    runs-on: ubuntu-latest",
      "    steps:",
      "      - name: Validate",
      "        run: ./scripts/validate.sh"
    ].join("\n")
  );

  writeText(path.join(fixtureRoot, "docs", "roadmap", "roadmap.md"), "# Fixture roadmap\n");
  writeText(path.join(fixtureRoot, "agents", "codex.md"), "codex\n");
  writeText(path.join(fixtureRoot, "agents", "claude.md"), "claude\n");
  writeText(path.join(fixtureRoot, "agents", "reviewer.md"), "reviewer\n");
  writeText(path.join(fixtureRoot, "prompts", "mega.md"), "mega\n");
  writeText(path.join(fixtureRoot, "prompts", "lean.md"), "lean\n");
  writeText(path.join(fixtureRoot, "prompts", "deploy.md"), "deploy\n");
  writeText(path.join(fixtureRoot, "tools", "validators", "enforce-runtime-guardrails.js"), "// fixture marker\n");
  writeText(path.join(fixtureRoot, "scripts", "validate.sh"), "#!/usr/bin/env bash\n");
  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 1;\n");

  writeJson(path.join(fixtureRoot, "docs", "roadmap", "state.json"), {
    current_phase: "BUILD-001",
    phase_type: "build",
    phase_status: "in_progress",
    active_task_id: "BUILD-001-T1",
    last_updated: updatedAt
  });

  writeJson(path.join(fixtureRoot, "state", "tasks.json"), {
    last_updated: updatedAt,
    tasks: [
      {
        id: "BUILD-001-T1",
        title: "Validate the fixture",
        status: "in_progress",
        phase: "BUILD-001",
        kind: "build",
        updated_at: updatedAt
      }
    ]
  });

  writeJson(path.join(fixtureRoot, "state", "risks.json"), {
    last_updated: updatedAt,
    risks: [
      {
        id: "RISK-TEST-001",
        severity: "medium",
        status: "unresolved",
        assigned_phase: "BUILD-001",
        note: "Fixture risk for validator testing."
      }
    ]
  });

  writeJson(path.join(fixtureRoot, "state", "decisions.json"), {
    last_updated: updatedAt,
    decisions: [
      {
        date: updatedAt,
        phase: "BUILD-001",
        summary: "Created fixture state."
      }
    ]
  });

  writeText(path.join(fixtureRoot, "artifacts", "build.log"), "build ok\n");
  writeText(path.join(fixtureRoot, "artifacts", "run.log"), "run ok\n");

  writeJson(path.join(fixtureRoot, "state", "artifacts.json"), {
    last_updated: updatedAt,
    code_changes_present: false,
    claims: {
      implementation: "in_progress",
      validation: "in_progress",
      deployment: "not_started"
    },
    external_inputs: [],
    evidence: {
      build: {
        status: "passed",
        updated_at: updatedAt,
        paths: ["artifacts/build.log"]
      },
      test: {
        metadata_only: true,
        status: "not_required",
        reason: "No code changes in fixture baseline.",
        updated_at: updatedAt,
        paths: []
      },
      run: {
        status: "passed",
        updated_at: updatedAt,
        paths: ["artifacts/run.log"]
      },
      deploy: {
        metadata_only: true,
        status: "not_required",
        reason: "Build phase fixture.",
        updated_at: updatedAt,
        paths: []
      }
    }
  });

  writeJson(path.join(fixtureRoot, "state", "handoff.json"), {
    last_updated: updatedAt,
    summary: "Fixture handoff summary.",
    next_action: "Continue validation.",
    discovered_issues: []
  });

  writeText(
    path.join(fixtureRoot, "state", "controller.md"),
    [
      "# Controller State",
      "",
      "current_state: ready_for_codex",
      "state_owner: Codex",
      "",
      "## allowed_transitions",
      "",
      "- ready_for_claude -> ready_for_codex",
      "- ready_for_claude -> blocked",
      "- ready_for_codex -> ready_for_review",
      "- ready_for_codex -> blocked",
      "- ready_for_review -> review_failed_fix_required",
      "- ready_for_review -> ready_for_claude",
      "- ready_for_review -> done",
      "- ready_for_review -> blocked",
      "- review_failed_fix_required -> ready_for_review",
      "- review_failed_fix_required -> ready_for_claude",
      "- review_failed_fix_required -> blocked",
      "",
      "## transition_rules",
      "",
      "- ready_for_claude -> ready_for_codex: planning complete",
      "- ready_for_claude -> blocked: planning blocked",
      "- ready_for_codex -> ready_for_review: implementation complete",
      "- ready_for_codex -> blocked: implementation blocked",
      "- ready_for_review -> review_failed_fix_required: review failed",
      "- ready_for_review -> ready_for_claude: planning_failure found",
      "- ready_for_review -> done: review passed",
      "- ready_for_review -> blocked: review blocked",
      "- review_failed_fix_required -> ready_for_review: fixes pushed",
      "- review_failed_fix_required -> ready_for_claude: replanning required",
      "- review_failed_fix_required -> blocked: remediation blocked",
      "",
      "## done_criteria",
      "",
      "- required GitHub checks are green",
      "- no blocking review comments remain",
      "",
      "## blocked_criteria",
      "",
      "- external intervention is required"
    ].join("\n")
  );

  writeText(
    path.join(fixtureRoot, "state", "current_task.md"),
    [
      "# Current Task",
      "",
      "task_id: BUILD-001-T1",
      "description: Validate the fixture task.",
      "branch: main",
      "pr_link: none",
      "owner: Codex",
      "current_state: ready_for_codex",
      "failure_type: none",
      "acceptance_criteria_reference: /ai/acceptance.md#t1",
      "last_action: Created the fixture state.",
      "next_action: Continue implementation."
    ].join("\n")
  );

  execFileSync("git", ["init", "-b", "main"], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["config", "user.name", "Codex"], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["config", "user.email", "codex@example.com"], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["add", "."], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["commit", "-m", "fixture"], { cwd: fixtureRoot, stdio: "ignore" });

  return fixtureRoot;
}

function writeArtifactsState(fixtureRoot, value) {
  writeJson(path.join(fixtureRoot, "state", "artifacts.json"), value);
}

function writeTasksState(fixtureRoot, value) {
  writeJson(path.join(fixtureRoot, "state", "tasks.json"), value);
}

function writeHandoffState(fixtureRoot, value) {
  writeJson(path.join(fixtureRoot, "state", "handoff.json"), value);
}

function runValidator(fixtureRoot) {
  try {
    const stdout = execFileSync(
      "node",
      [
        validatorPath,
        "--repo",
        fixtureRoot,
        "--config",
        path.join(fixtureRoot, "ai.config.json"),
        "--base",
        "main"
      ],
      {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"]
      }
    );

    return { status: 0, output: stdout };
  } catch (error) {
    return {
      status: error.status ?? 1,
      output: `${error.stdout ?? ""}${error.stderr ?? ""}`
    };
  }
}

test("validator passes for a clean standard fixture", () => {
  const fixtureRoot = buildFixtureRoot();

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 0);
  assert.match(result.output, /^PASS/m);
});

test("validator fails when code changes skip task artifact and handoff updates", () => {
  const fixtureRoot = buildFixtureRoot();

  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 2;\n");

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(result.output, /state\/tasks\.json not updated after progress change/);
  assert.match(result.output, /state\/artifacts\.json not updated after progress change/);
  assert.match(result.output, /state\/handoff\.json not updated after progress change/);
});

test("validator passes when code changes include updated state and file-backed evidence", () => {
  const fixtureRoot = buildFixtureRoot();
  const updatedAt = "2026-04-05T08:00:00Z";

  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 2;\n");
  writeText(path.join(fixtureRoot, "artifacts", "build-updated.log"), "build updated\n");
  writeText(path.join(fixtureRoot, "artifacts", "test-updated.log"), "test updated\n");
  writeText(path.join(fixtureRoot, "artifacts", "run-updated.log"), "run updated\n");

  writeTasksState(fixtureRoot, {
    last_updated: updatedAt,
    tasks: [
      {
        id: "BUILD-001-T1",
        title: "Validate the fixture",
        status: "in_progress",
        phase: "BUILD-001",
        kind: "build",
        updated_at: updatedAt
      }
    ]
  });

  writeArtifactsState(fixtureRoot, {
    last_updated: updatedAt,
    code_changes_present: true,
    claims: {
      implementation: "in_progress",
      validation: "in_progress",
      deployment: "not_started"
    },
    external_inputs: [],
    evidence: {
      build: {
        status: "passed",
        updated_at: updatedAt,
        paths: ["artifacts/build-updated.log"]
      },
      test: {
        status: "passed",
        updated_at: updatedAt,
        paths: ["artifacts/test-updated.log"]
      },
      run: {
        status: "passed",
        updated_at: updatedAt,
        paths: ["artifacts/run-updated.log"]
      },
      deploy: {
        metadata_only: true,
        status: "not_required",
        reason: "Build phase fixture.",
        updated_at: updatedAt,
        paths: []
      }
    }
  });

  writeHandoffState(fixtureRoot, {
    last_updated: updatedAt,
    summary: "Code change executed with updated evidence.",
    next_action: "Proceed to the next fixture step.",
    discovered_issues: []
  });

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 0);
  assert.match(result.output, /^PASS/m);
});

test("validator fails when review or CI failure is routed back to Claude", () => {
  const fixtureRoot = buildFixtureRoot();

  writeText(
    path.join(fixtureRoot, "state", "controller.md"),
    [
      "# Controller State",
      "",
      "current_state: ready_for_claude",
      "state_owner: Claude",
      "",
      "## allowed_transitions",
      "",
      "- ready_for_claude -> ready_for_codex",
      "- ready_for_claude -> blocked",
      "- ready_for_codex -> ready_for_review",
      "- ready_for_codex -> blocked",
      "- ready_for_review -> review_failed_fix_required",
      "- ready_for_review -> ready_for_claude",
      "- ready_for_review -> done",
      "- ready_for_review -> blocked",
      "- review_failed_fix_required -> ready_for_review",
      "- review_failed_fix_required -> ready_for_claude",
      "- review_failed_fix_required -> blocked",
      "",
      "## transition_rules",
      "",
      "- ready_for_claude -> ready_for_codex: planning complete",
      "- ready_for_claude -> blocked: planning blocked",
      "- ready_for_codex -> ready_for_review: implementation complete",
      "- ready_for_codex -> blocked: implementation blocked",
      "- ready_for_review -> review_failed_fix_required: review failed",
      "- ready_for_review -> ready_for_claude: planning_failure found",
      "- ready_for_review -> done: review passed",
      "- ready_for_review -> blocked: review blocked",
      "- review_failed_fix_required -> ready_for_review: fixes pushed",
      "- review_failed_fix_required -> ready_for_claude: replanning required",
      "- review_failed_fix_required -> blocked: remediation blocked",
      "",
      "## done_criteria",
      "",
      "- required GitHub checks are green",
      "- no blocking review comments remain",
      "",
      "## blocked_criteria",
      "",
      "- external intervention is required"
    ].join("\n")
  );

  writeText(
    path.join(fixtureRoot, "state", "current_task.md"),
    [
      "# Current Task",
      "",
      "task_id: BUILD-001-T1",
      "description: Validate the fixture task.",
      "branch: main",
      "pr_link: none",
      "owner: Claude",
      "current_state: ready_for_claude",
      "failure_type: review_failure",
      "acceptance_criteria_reference: /ai/acceptance.md#t1",
      "last_action: Incorrectly routed review failure to planning.",
      "next_action: Replan the task."
    ].join("\n")
  );

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(
    result.output,
    /ci_failure and review_failure require current_state review_failed_fix_required/
  );
  assert.match(
    result.output,
    /ready_for_claude only allows failure_type none or planning_failure/
  );
});
