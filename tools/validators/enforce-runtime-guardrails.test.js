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
  const updatedOn = "2026-04-04";
  const unresolvedRisk = {
    id: "RISK-TEST-001",
    severity: "medium",
    status: "unresolved",
    assigned_phase: "OPS-TEST",
    note: "Fixture risk for validator testing."
  };

  writeText(
    path.join(fixtureRoot, ".github", "workflows", "ci.yml"),
    [
      "name: CI",
      "on:",
      "  pull_request:",
      "",
      "env:",
      "  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\"",
      "",
      "jobs:",
      "  runtime-guardrails:",
      "    runs-on: ubuntu-latest",
      "    steps:",
      "      - name: Run runtime guardrails validator",
      "        run: node tools/validators/enforce-runtime-guardrails.js"
    ].join("\n")
  );

  writeText(path.join(fixtureRoot, "docs", "roadmap", "roadmap.md"), "# Fixture roadmap\n");
  writeText(path.join(fixtureRoot, "agents", "codex.md"), "codex\n");
  writeText(path.join(fixtureRoot, "agents", "claude.md"), "claude\n");
  writeText(path.join(fixtureRoot, "agents", "reviewer.md"), "reviewer\n");
  writeText(path.join(fixtureRoot, "prompts", "mega.md"), "mega\n");
  writeText(path.join(fixtureRoot, "prompts", "lean.md"), "lean\n");
  writeText(path.join(fixtureRoot, "prompts", "deploy.md"), "deploy\n");
  writeText(path.join(fixtureRoot, "tools", "validators", "enforce-runtime-guardrails.js"), "// fixture copy marker\n");
  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 1;\n");

  writeJson(path.join(fixtureRoot, "docs", "roadmap", "state.json"), {
    current_phase: {
      id: "OPS-TEST",
      name: "Validator Fixture",
      status: "in_progress"
    },
    risk_remediation_phases: [
      {
        id: "OPS-TEST",
        name: "Validator Fixture",
        priority: "low",
        grouped_risks: ["RISK-TEST-001"],
        scope: "Fixture scope."
      }
    ],
    upcoming_phases: [],
    completed_phases: [],
    opportunities: [],
    incidents: [],
    risks: [
      {
        id: "RISK-TEST-001",
        description: "Fixture risk",
        severity: "medium",
        impact: "Fixture impact",
        mitigation: "Fixture mitigation",
        affected_components: ["tests"],
        phase_association: "OPS-TEST",
        status: "unresolved"
      }
    ],
    tasks: {
      active: ["OPS-TEST-T1"],
      completed: []
    },
    decisions: [],
    last_updated: updatedOn
  });

  writeJson(path.join(fixtureRoot, "state", "tasks.json"), {
    updated_on: updatedOn,
    active: [
      {
        id: "OPS-TEST-T1",
        phase: "OPS-TEST",
        title: "Fixture task",
        status: "pending",
        blocking_for_phase_completion: true
      }
    ],
    completed: []
  });

  writeJson(path.join(fixtureRoot, "state", "risks.json"), {
    updated_on: updatedOn,
    resolved: [],
    unresolved: [unresolvedRisk]
  });

  writeJson(path.join(fixtureRoot, "state", "decisions.json"), {
    updated_on: updatedOn,
    entries: [
      {
        date: updatedOn,
        phase: "OPS-TEST",
        summary: "Created fixture state."
      }
    ]
  });

  writeJson(path.join(fixtureRoot, "state", "session.json"), {
    updated_on: updatedOn,
    phase: {
      id: "OPS-TEST",
      name: "Validator Fixture",
      status: "in_progress"
    },
    roadmap_phase_context: {
      id: "OPS-TEST",
      name: "Validator Fixture",
      status: "in_progress"
    },
    branch: "main",
    execution_summary: "Fixture summary.",
    evidence: [
      {
        id: "OPS-TEST-E1",
        date: updatedOn,
        phase: "OPS-TEST",
        scope: "fixture-validation",
        type: "validation",
        command: "node tools/validators/enforce-runtime-guardrails.js",
        result: "PASS",
        summary: "Fixture validation entry."
      }
    ]
  });

  execFileSync("git", ["init", "-b", "main"], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["config", "user.name", "Codex"], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["config", "user.email", "codex@example.com"], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["add", "."], { cwd: fixtureRoot, stdio: "ignore" });
  execFileSync("git", ["commit", "-m", "fixture"], { cwd: fixtureRoot, stdio: "ignore" });

  return fixtureRoot;
}

function writeFixtureSession(fixtureRoot, evidence, phase = { id: "OPS-TEST", name: "Validator Fixture" }) {
  writeJson(path.join(fixtureRoot, "state", "session.json"), {
    updated_on: "2026-04-04",
    phase: {
      id: phase.id,
      name: phase.name,
      status: "in_progress"
    },
    roadmap_phase_context: {
      id: phase.id,
      name: phase.name,
      status: "in_progress"
    },
    branch: "main",
    execution_summary: "Fixture summary.",
    evidence
  });
}

function runValidator(fixtureRoot) {
  try {
    const stdout = execFileSync("node", [validatorPath], {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        RUNTIME_GUARDRAILS_REPO_ROOT: fixtureRoot,
        RUNTIME_GUARDRAILS_BASE_REF: "main"
      },
      stdio: ["ignore", "pipe", "pipe"]
    });

    return { status: 0, output: stdout };
  } catch (error) {
    return {
      status: error.status ?? 1,
      output: `${error.stdout ?? ""}${error.stderr ?? ""}`
    };
  }
}

test("validator fails when FAIL evidence omits risk_ids", () => {
  const fixtureRoot = buildFixtureRoot();

  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 2;\n");
  writeFixtureSession(fixtureRoot, [
    {
      id: "OPS-TEST-E1",
      date: "2026-04-04",
      phase: "OPS-TEST",
      scope: "fixture-validation",
      type: "validation",
      command: "node tools/validators/enforce-runtime-guardrails.js",
      result: "FAIL",
      summary: "Missing risk IDs should fail validation."
    }
  ]);

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(
    result.output,
    /Evidence entry OPS-TEST-E1 must reference risk_ids when result is FAIL\./
  );
});

test("validator passes when FAIL evidence includes risk_ids", () => {
  const fixtureRoot = buildFixtureRoot();

  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 2;\n");
  writeFixtureSession(fixtureRoot, [
    {
      id: "OPS-TEST-E1",
      date: "2026-04-04",
      phase: "OPS-TEST",
      scope: "fixture-validation",
      type: "validation",
      command: "node tools/validators/enforce-runtime-guardrails.js",
      result: "FAIL",
      risk_ids: ["RISK-TEST-001"],
      summary: "Known failure with mapped risk."
    }
  ]);

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 0);
  assert.match(result.output, /^PASS/m);
});

test("validator allows NOT RUN evidence without risk_ids in docs phases", () => {
  const fixtureRoot = buildFixtureRoot();

  writeJson(path.join(fixtureRoot, "docs", "roadmap", "state.json"), {
    current_phase: {
      id: "DOC-TEST",
      name: "Documentation Follow-up",
      status: "in_progress"
    },
    risk_remediation_phases: [
      {
        id: "OPS-TEST",
        name: "Validator Fixture",
        priority: "low",
        grouped_risks: ["RISK-TEST-001"],
        scope: "Fixture scope."
      }
    ],
    upcoming_phases: [],
    completed_phases: [],
    opportunities: [],
    incidents: [],
    risks: [
      {
        id: "RISK-TEST-001",
        description: "Fixture risk",
        severity: "medium",
        impact: "Fixture impact",
        mitigation: "Fixture mitigation",
        affected_components: ["tests"],
        phase_association: "OPS-TEST",
        status: "unresolved"
      }
    ],
    tasks: {
      active: ["OPS-TEST-T1"],
      completed: []
    },
    decisions: [],
    last_updated: "2026-04-04"
  });

  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 2;\n");
  writeFixtureSession(
    fixtureRoot,
    [
      {
        id: "DOC-TEST-E1",
        date: "2026-04-04",
        phase: "DOC-TEST",
        scope: "docs-validation",
        type: "validation",
        command: "node tools/validators/enforce-runtime-guardrails.js",
        result: "NOT RUN",
        summary: "Docs-phase evidence can defer execution without a mapped risk."
      }
    ],
    { id: "DOC-TEST", name: "Documentation Follow-up" }
  );

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 0);
  assert.match(result.output, /^PASS/m);
});

test("validator requires risk_ids for NOT RUN evidence outside docs phases", () => {
  const fixtureRoot = buildFixtureRoot();

  writeText(path.join(fixtureRoot, "src", "app.js"), "module.exports = 2;\n");
  writeFixtureSession(fixtureRoot, [
    {
      id: "OPS-TEST-E1",
      date: "2026-04-04",
      phase: "OPS-TEST",
      scope: "fixture-validation",
      type: "validation",
      command: "node tools/validators/enforce-runtime-guardrails.js",
      result: "NOT RUN",
      summary: "Non-docs NOT RUN entries must carry risks."
    }
  ]);

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(
    result.output,
    /Evidence entry OPS-TEST-E1 must reference risk_ids when result is NOT RUN\./
  );
});
