# Plan

## Goal

BugNarrator becomes THE bug narration tool — the default way QA engineers, product managers, and developers capture, document, and communicate bugs. Every software team that does manual testing or review should use BugNarrator instead of writing bug reports by hand, recording Loom videos, or pasting screenshots into Jira.

## North Star

"Record. Narrate. Ship the bug report." A tester talks through a bug while BugNarrator records audio, captures screenshots, transcribes everything, extracts structured issues with AI, and exports directly to the team's issue tracker. The entire flow from "I found a bug" to "ticket filed with reproduction steps" takes under 2 minutes.

## Why BugNarrator Wins

**vs Loom/screen recording:** Loom captures video but doesn't extract bugs, doesn't create tickets, doesn't produce structured reproduction steps. Developers still have to watch the video and manually create tickets.

**vs manual bug reports:** Writing a good bug report takes 10-15 minutes. BugNarrator produces a better report in 2 minutes because narration captures context that written reports miss.

**vs screenshot tools (Snagit, CleanShot):** Screenshots without narration lose the "why" — why the tester clicked there, what they expected, what surprised them. BugNarrator captures the reasoning.

## AI Integration Strategy

AI is not a feature — it's the core engine that transforms raw narration into actionable engineering artifacts.

### 1. Intelligent Issue Extraction (exists, enhance)
Current: OpenAI extracts issues from transcript. Enhance: classify by severity, deduplicate against existing issues in the tracker, suggest affected component/area based on what's shown in screenshots.

### 2. Reproduction Step Generation (new)
AI analyzes the narration timeline + screenshots to generate step-by-step reproduction instructions. "1. Navigate to Settings > Accounts. 2. Click 'Add Account'. 3. Enter email without @ symbol. 4. Click Submit. Expected: validation error. Actual: blank screen." This is the killer feature — no tester writes repro steps this good.

### 3. Smart Screenshot Annotation (new)
AI analyzes screenshots and auto-annotates: highlights the UI element being discussed, draws attention arrows, labels the relevant area. The tester narrates "this button doesn't work" and AI marks which button in the screenshot.

### 4. Similar Bug Detection (new)
Before exporting to Jira/GitHub, AI checks existing open issues for duplicates or related bugs. Shows "This may be related to PROJ-142: Login form validation broken" with confidence score. Reduces duplicate tickets.

### 5. Session Intelligence (new)
AI summarizes the testing session: "Tested the account settings flow. Found 3 bugs (1 critical, 2 minor). Coverage: settings page, account creation, email validation. Not tested: password reset, profile editing." Gives product managers a testing coverage view.

## Phases

### Phase 1: Core Polish + Reproduction Steps (N1-N3)
Make the existing flow bulletproof and add AI-generated reproduction steps.

### Phase 2: Smart Features (N4-N6)
Screenshot annotation, duplicate detection, session intelligence.

### Phase 3: Team + Enterprise (N7-N9)
Team shared library, enterprise SSO, session analytics.

## Constraints

- macOS-first (Windows port exists but macOS leads)
- Menu bar app UX — lightweight, always available, never in the way
- AI outputs must be editable before export (human review, not auto-file)
- No subscription required for core features (API key model)
- One task at a time, one PR per task (or batched related tasks)
- Tests required with every code change
