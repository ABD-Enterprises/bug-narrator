#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const repoRoot = process.env.RUNTIME_GUARDRAILS_REPO_ROOT
  ? path.resolve(process.env.RUNTIME_GUARDRAILS_REPO_ROOT)
  : path.resolve(__dirname, "..", "..");
process.chdir(repoRoot);

const failures = [];

function fail(message) {
  failures.push(message);
}

function readJson(relativePath) {
  const absolutePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(absolutePath)) {
    fail(`Missing required file: ${relativePath}`);
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  } catch (error) {
    fail(`Invalid JSON in ${relativePath}: ${error.message}`);
    return null;
  }
}

function git(args, { allowFailure = false } = {}) {
  try {
    return execFileSync("git", args, {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    }).trim();
  } catch (error) {
    if (allowFailure) {
      return "";
    }

    fail(`git ${args.join(" ")} failed: ${error.stderr ? error.stderr.toString().trim() : error.message}`);
    return "";
  }
}

function parseCliBaseRef() {
  const index = process.argv.indexOf("--base-ref");
  if (index !== -1 && process.argv[index + 1]) {
    return process.argv[index + 1];
  }

  return "";
}

function refExists(ref) {
  if (!ref) {
    return false;
  }

  return git(["rev-parse", "--verify", ref], { allowFailure: true }) !== "";
}

function determineBaseRef() {
  const candidates = [];
  const cliBaseRef = parseCliBaseRef();

  if (cliBaseRef) {
    candidates.push(cliBaseRef);
  }

  if (process.env.RUNTIME_GUARDRAILS_BASE_REF) {
    candidates.push(process.env.RUNTIME_GUARDRAILS_BASE_REF);
  }

  if (process.env.GITHUB_BASE_REF) {
    candidates.push(`origin/${process.env.GITHUB_BASE_REF}`);
    candidates.push(process.env.GITHUB_BASE_REF);
  }

  candidates.push("origin/main", "main", "HEAD~1");

  return candidates.find(refExists) || "HEAD~1";
}

function listChangedFiles(baseRef) {
  const changed = new Set();
  const mergeBase = git(["merge-base", "HEAD", baseRef], { allowFailure: true });
  const ranges = [];

  if (mergeBase) {
    ranges.push(["diff", "--name-only", `${mergeBase}..HEAD`]);
  } else if (refExists(baseRef)) {
    ranges.push(["diff", "--name-only", `${baseRef}..HEAD`]);
  }

  ranges.push(["diff", "--name-only"]);
  ranges.push(["diff", "--name-only", "--cached"]);

  for (const args of ranges) {
    const output = git(args, { allowFailure: true });
    for (const line of output.split("\n")) {
      const value = line.trim();
      if (value) {
        changed.add(value);
      }
    }
  }

  return Array.from(changed).sort();
}

function readJsonAtRef(ref, relativePath) {
  const content = git(["show", `${ref}:${relativePath}`], { allowFailure: true });
  if (!content) {
    return null;
  }

  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`Invalid JSON in ${relativePath} at ${ref}: ${error.message}`);
    return null;
  }
}

function normalizePhase(value) {
  if (!value) {
    return { id: "", name: "", status: "" };
  }

  if (typeof value === "string") {
    return { id: value, name: value, status: "" };
  }

  return {
    id: value.id || "",
    name: value.name || value.id || "",
    status: value.status || ""
  };
}

function isDocsPhase(phase) {
  const label = `${phase.id} ${phase.name}`.toLowerCase();
  return /(doc|docs|documentation|roadmap|onboarding|spec)/.test(label);
}

function isDeployPhase(phase) {
  const label = `${phase.id} ${phase.name}`.toLowerCase();
  return /(deploy|release|promotion|publish)/.test(label);
}

function isDocumentationPath(relativePath) {
  return (
    relativePath.startsWith("docs/") ||
    relativePath.startsWith("state/") ||
    relativePath.startsWith("agents/") ||
    relativePath.startsWith("prompts/") ||
    /\.mdx?$/i.test(relativePath) ||
    /\.txt$/i.test(relativePath)
  );
}

function sortedIds(values) {
  return [...values].sort();
}

function arraysEqual(left, right) {
  return JSON.stringify(sortedIds(left)) === JSON.stringify(sortedIds(right));
}

function readText(relativePath) {
  const absolutePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(absolutePath)) {
    fail(`Missing required file: ${relativePath}`);
    return "";
  }

  return fs.readFileSync(absolutePath, "utf8");
}

function listWorkflowFiles() {
  const workflowsDir = path.join(repoRoot, ".github", "workflows");
  if (!fs.existsSync(workflowsDir)) {
    fail("Missing required workflows directory: .github/workflows");
    return [];
  }

  return fs
    .readdirSync(workflowsDir)
    .filter(name => name.endsWith(".yml") || name.endsWith(".yaml"))
    .sort()
    .map(name => path.join(".github", "workflows", name));
}

function validateActionVersion(relativePath, content, actionName, minimumMajor) {
  const pattern = new RegExp(`uses:\\s*${actionName.replace("/", "\\/")}@v(\\d+)`, "g");
  let matched = false;
  let match;

  while ((match = pattern.exec(content)) !== null) {
    matched = true;
    const major = Number.parseInt(match[1], 10);
    if (Number.isNaN(major) || major < minimumMajor) {
      fail(`${relativePath} must use ${actionName}@v${minimumMajor}+ for Node24 compatibility.`);
    }
  }

  return matched;
}

[
  "docs/roadmap/roadmap.md",
  "docs/roadmap/state.json",
  "state/session.json",
  "state/tasks.json",
  "state/risks.json",
  "state/decisions.json",
  "agents/codex.md",
  "agents/claude.md",
  "agents/reviewer.md",
  "prompts/mega.md",
  "prompts/lean.md",
  "prompts/deploy.md",
  "tools/validators/enforce-runtime-guardrails.js",
  ".github/workflows/ci.yml"
].forEach(relativePath => {
  if (!fs.existsSync(path.join(repoRoot, relativePath))) {
    fail(`Missing required repository contract file: ${relativePath}`);
  }
});

const roadmapState = readJson("docs/roadmap/state.json");
const sessionState = readJson("state/session.json");
const tasksState = readJson("state/tasks.json");
const risksState = readJson("state/risks.json");
const decisionsState = readJson("state/decisions.json");

if (!roadmapState || !sessionState || !tasksState || !risksState || !decisionsState) {
  if (failures.length) {
    console.error("FAIL");
    failures.forEach(message => console.error(`- ${message}`));
    process.exit(1);
  }
}

const workflowContent = readText(".github/workflows/ci.yml");
if (!workflowContent.includes("pull_request:")) {
  fail(".github/workflows/ci.yml must run on pull_request.");
}
if (!workflowContent.includes("node tools/validators/enforce-runtime-guardrails.js")) {
  fail(".github/workflows/ci.yml must invoke tools/validators/enforce-runtime-guardrails.js.");
}
if (!workflowContent.includes('FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"')) {
  fail(".github/workflows/ci.yml must force JavaScript actions onto Node24 during validation.");
}

const workflowFiles = listWorkflowFiles();
for (const workflowFile of workflowFiles) {
  const content = readText(workflowFile);
  const usesTrackedAction = [
    validateActionVersion(workflowFile, content, "actions/checkout", 5),
    validateActionVersion(workflowFile, content, "actions/setup-node", 5),
    validateActionVersion(workflowFile, content, "actions/setup-python", 6),
    validateActionVersion(workflowFile, content, "actions/setup-dotnet", 5),
    validateActionVersion(workflowFile, content, "actions/upload-artifact", 6)
  ].some(Boolean);

  if (usesTrackedAction && !content.includes('FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"')) {
    fail(`${workflowFile} must force JavaScript actions onto Node24 during validation.`);
  }
}

if (!roadmapState.current_phase) {
  fail("docs/roadmap/state.json must include current_phase.");
}
if (!roadmapState.last_updated || typeof roadmapState.last_updated !== "string") {
  fail("docs/roadmap/state.json must include last_updated.");
}
if (!roadmapState.tasks || !Array.isArray(roadmapState.tasks.active) || !Array.isArray(roadmapState.tasks.completed)) {
  fail("docs/roadmap/state.json must include tasks.active and tasks.completed arrays.");
}
if (!Array.isArray(roadmapState.risks)) {
  fail("docs/roadmap/state.json must include a risks array.");
}

["updated_on"].forEach(key => {
  if (!sessionState[key]) {
    fail(`state/session.json must include ${key}.`);
  }
  if (!tasksState[key]) {
    fail(`state/tasks.json must include ${key}.`);
  }
  if (!risksState[key]) {
    fail(`state/risks.json must include ${key}.`);
  }
  if (!decisionsState[key]) {
    fail(`state/decisions.json must include ${key}.`);
  }
});

if (roadmapState.last_updated !== sessionState.updated_on) {
  fail("docs/roadmap/state.json last_updated must match state/session.json updated_on.");
}
if (tasksState.updated_on !== sessionState.updated_on) {
  fail("state/tasks.json updated_on must match state/session.json updated_on.");
}
if (risksState.updated_on !== sessionState.updated_on) {
  fail("state/risks.json updated_on must match state/session.json updated_on.");
}
if (decisionsState.updated_on !== sessionState.updated_on) {
  fail("state/decisions.json updated_on must match state/session.json updated_on.");
}

if (!Array.isArray(tasksState.active) || !Array.isArray(tasksState.completed)) {
  fail("state/tasks.json must contain active and completed arrays.");
}

const taskIds = {
  active: tasksState.active.map(task => task.id),
  completed: tasksState.completed.map(task => task.id)
};
if (!arraysEqual(taskIds.active, roadmapState.tasks.active)) {
  fail("docs/roadmap/state.json tasks.active must mirror state/tasks.json active task IDs.");
}
if (!arraysEqual(taskIds.completed, roadmapState.tasks.completed)) {
  fail("docs/roadmap/state.json tasks.completed must mirror state/tasks.json completed task IDs.");
}

const unresolvedRisks = Array.isArray(risksState.unresolved) ? risksState.unresolved : [];
const resolvedRisks = Array.isArray(risksState.resolved) ? risksState.resolved : [];
const riskIds = new Set([...unresolvedRisks, ...resolvedRisks].map(risk => risk.id));
const roadmapRiskIds = new Set((roadmapState.risks || []).map(risk => risk.id));

for (const riskId of riskIds) {
  if (!roadmapRiskIds.has(riskId)) {
    fail(`docs/roadmap/state.json risks must include ${riskId} from state/risks.json.`);
  }
}

const remediationPhaseIds = new Set([
  normalizePhase(roadmapState.current_phase).id,
  ...(roadmapState.risk_remediation_phases || []).map(phase => phase.id),
  ...(roadmapState.upcoming_phases || []).map(phase => phase.id)
]);

for (const risk of unresolvedRisks) {
  if (!risk.assigned_phase || !remediationPhaseIds.has(risk.assigned_phase)) {
    fail(`Unresolved risk ${risk.id} must keep an assigned remediation phase.`);
  }
}

if (!Array.isArray(sessionState.evidence) || sessionState.evidence.length === 0) {
  fail("state/session.json must include evidence entries for the current execution slice.");
}

const allowedResults = new Set(["PASS", "FAIL", "NOT RUN", "BLOCKED"]);
const allowedTypes = new Set(["build", "test", "run", "validation", "deploy"]);
const roadmapPhase = normalizePhase(roadmapState.current_phase);

for (const entry of sessionState.evidence || []) {
  if (!entry.id || !entry.phase || !entry.type || !entry.command || !entry.result || !entry.summary || !entry.date) {
    fail(`Evidence entries must include id, phase, type, command, result, summary, and date. Invalid entry: ${JSON.stringify(entry)}`);
    continue;
  }

  if (!allowedTypes.has(entry.type)) {
    fail(`Evidence entry ${entry.id} has unsupported type ${entry.type}.`);
  }
  if (!allowedResults.has(entry.result)) {
    fail(`Evidence entry ${entry.id} has unsupported result ${entry.result}.`);
  }

  const needsRiskIds =
    entry.result === "FAIL" ||
    entry.result === "BLOCKED" ||
    (entry.result === "NOT RUN" && !isDocsPhase(roadmapPhase));

  if (needsRiskIds && (!Array.isArray(entry.risk_ids) || entry.risk_ids.length === 0)) {
    fail(`Evidence entry ${entry.id} must reference risk_ids when result is ${entry.result}.`);
  }

  for (const riskId of entry.risk_ids || []) {
    if (!riskIds.has(riskId)) {
      fail(`Evidence entry ${entry.id} references missing risk ${riskId}. Add it to state/risks.json and docs/roadmap/state.json.`);
    }
  }
}

const baseRef = determineBaseRef();
const changedFiles = listChangedFiles(baseRef);
const stateFiles = new Set([
  "docs/roadmap/state.json",
  "state/session.json",
  "state/tasks.json",
  "state/risks.json",
  "state/decisions.json"
]);

if (changedFiles.length > 0 && !changedFiles.some(file => stateFiles.has(file))) {
  fail("Work progressed without updating the canonical state files.");
}

const hasCodeChanges = changedFiles.some(file => !isDocumentationPath(file));
const executableEvidence = (sessionState.evidence || []).filter(entry => allowedTypes.has(entry.type));
if (hasCodeChanges && executableEvidence.length === 0) {
  fail("Code, workflow, or validator changes require recorded evidence in state/session.json.");
}

const baseRisksState = readJsonAtRef(baseRef, "state/risks.json");
if (baseRisksState && Array.isArray(baseRisksState.unresolved)) {
  const previousUnresolved = new Set(baseRisksState.unresolved.map(risk => risk.id));
  const currentRiskIds = new Set([...unresolvedRisks, ...resolvedRisks].map(risk => risk.id));

  for (const riskId of previousUnresolved) {
    if (!currentRiskIds.has(riskId)) {
      fail(`Unresolved risk ${riskId} was removed without being preserved or explicitly resolved.`);
    }
  }
}

if ((roadmapState.current_phase?.status || "").toLowerCase() === "completed") {
  const phaseId = roadmapPhase.id;
  const blockingTasks = tasksState.active.filter(task => task.phase === phaseId && task.blocking_for_phase_completion && task.status !== "completed");
  if (blockingTasks.length > 0) {
    fail(`Phase ${phaseId} cannot be completed while blocking tasks remain active: ${blockingTasks.map(task => task.id).join(", ")}.`);
  }

  const phaseEvidence = (sessionState.evidence || []).filter(entry => entry.phase === phaseId);
  if (isDeployPhase(roadmapPhase)) {
    if (!phaseEvidence.some(entry => entry.type === "deploy" && entry.result === "PASS")) {
      fail(`Deploy phase ${phaseId} requires PASS deploy evidence before completion.`);
    }
  } else if (!isDocsPhase(roadmapPhase)) {
    if (!phaseEvidence.some(entry => ["build", "test", "run", "validation"].includes(entry.type) && entry.result === "PASS")) {
      fail(`Phase ${phaseId} cannot be completed without PASS build, test, run, or validation evidence.`);
    }
  }
}

if (failures.length > 0) {
  console.error("FAIL");
  failures.forEach(message => console.error(`- ${message}`));
  process.exit(1);
}

console.log("PASS");
console.log(`Validated runtime guardrails against ${baseRef}.`);
console.log(`Changed files inspected: ${changedFiles.length}.`);
