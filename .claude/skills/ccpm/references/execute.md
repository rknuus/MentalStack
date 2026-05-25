# Execute — Start Building with Parallel Agents

This phase covers analyzing GitHub issues for parallel work streams and launching agents to execute them.

---

## Issue Analysis

**Trigger**: User wants to understand how to parallelize work on an issue before starting.

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- Find the local task file: check `.ccpm/initiatives/*/<epic>/<N>.md` first, then search for `github:.*issues/<N>` in frontmatter.
- If not found: "❌ No local task for issue #<N>. Run a sync first."

### Process

Get issue details: `gh issue view <N> --json title,body,labels`
If GitHub is unavailable, read task details from local `.ccpm/` task files instead.

Read the local task file fully. Identify independent work streams by asking:
- Which files will be created/modified?
- Which changes can happen simultaneously without conflict?
- What are the dependencies between changes?

**Common stream patterns:**
- Database Layer: schema, migrations, models
- Service Layer: business logic, data access
- API Layer: endpoints, validation, middleware
- UI Layer: components, pages, styles
- Test Layer: unit tests, integration tests

Create `.ccpm/initiatives/<initiative>/<epic_name>/<N>-analysis.md`:

```markdown
---
issue: <N>
title: <title>
analyzed: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
estimated_hours: <total>
parallelization_factor: <1.0-5.0>
---

# Parallel Work Analysis: Issue #<N>

## Overview

## Parallel Streams

### Stream A: <Name>
**Scope**:
**Files**:
**Can Start**: immediately
**Estimated Hours**:
**Dependencies**: none

### Stream B: <Name>
**Scope**:
**Files**:
**Can Start**: after Stream A
**Dependencies**: Stream A

## Coordination Points
### Shared Files
### Sequential Requirements

## Conflict Risk Assessment

## Parallelization Strategy

## Expected Timeline
- With parallel execution: <max_stream_hours>h wall time
- Without: <sum_all_hours>h
- Efficiency gain: <pct>%
```

**Output**: "✅ Analysis complete for issue #<N> — N parallel streams identified. Ready to start? Say: start issue <N>"

---

## Starting an Issue

**Trigger**: User wants to begin work on a specific GitHub issue.

### Preflight
0. **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
1. **Mode detection**: After the root check, run the canonical [Mode-Detection Preflight](conventions.md#mode-detection-preflight) so `CCPM_TRACKED`, `METHOD_DIR`, `METHOD_TRACKED`, `WORKTREE_ACTIVE`, `ONLINE`, and `SYNC_ENABLED` are available for the rest of this phase. The flags are passed through to every agent launched below.
2. Verify issue exists and is open (only when `SYNC_ENABLED=true`): `gh issue view <N> --json state,title,labels,body`. If `SYNC_ENABLED=false`, read the local task file instead.
3. Find local task file (as above).
4. Check for analysis file: `.ccpm/initiatives/<initiative>/<epic>/<N>-analysis.md` — if missing, run analysis first (or do both in sequence: analyze then start).
5. **Resolve working directory**: use `WORKTREE_ACTIVE` from the mode detection.
   - If `WORKTREE_ACTIVE=true`: verify worktree exists at `../<repo-basename>-<initiative-name>/`. Use that directory as the working directory for agents. If missing: "❌ Worktree not found. Run: `@ccpm worktree enable <initiative-name>`"
   - If `WORKTREE_ACTIVE=false`: verify initiative branch is checked out via `git branch --show-current`. If not, check it out. Agents work in the project root.

### Process

**Step 1 — Read the analysis**, identify which streams can start immediately vs. which have dependencies.

**Step 2 — Create progress tracking:**
```bash
mkdir -p .ccpm/initiatives/<initiative>/<epic>/updates/<N>
```

Get the current timestamp:
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Create `.ccpm/initiatives/<initiative>/<epic>/updates/<N>/stream-<X>.md` for each stream:
```markdown
---
issue: <N>
stream: <stream_name>
started: <datetime>
status: in_progress
---
## Scope
## Progress
- Starting implementation
```

**Step 3 — Launch parallel agents** for each stream that can start immediately. The agent's commit and push surface contracts to two coordinator-script invocations — the agent never composes git commands directly.

```yaml
Task:
  description: "Issue #<N> Stream <X>"
  subagent_type: "general-purpose"
  prompt: |
    You are working on Issue #<N>.

    **Working directory contract.** Your working directory is:
      - the project root (`<repo-toplevel>`) when no worktree is in use, OR
      - the sibling worktree path `../<repo-basename>-<initiative-name>/` when this initiative has `worktree: true`.
    The orchestrator has placed you in the right directory before launching this prompt. Your responsibilities while running:
      - Run every Bash command as a bare relative-path form. The cwd is already correct.
      - **Never** prepend `cd <path> && …` to any command. Compound `cd && <cmd>` invocations trip Claude Code's risky-command monitor and force a per-call approval prompt.
      - **Never** use `git -C <path> …` form. The cwd is correct; bare `git` is sufficient. (See `references/command-safety.md` for the rationale.)
      - **Never** chain commands with `&&`, `||`, or `;`. One operation per Bash call.

    Branch: initiative/<initiative-name>

    Your stream: <stream_name>
    Your scope — files to modify: <file_patterns>
    Work to complete: <stream_description>

    Instructions:
    1. Read full task from: .ccpm/initiatives/<initiative>/<epic>/<N>.md
    2. Read analysis from: .ccpm/initiatives/<initiative>/<epic>/<N>-analysis.md
    3. Work ONLY in your assigned files.
    4. Commit frequently via the coordinator script (recipe below).
    5. Update progress in: .ccpm/initiatives/<initiative>/<epic>/updates/<N>/stream-<X>.md
    6. If you need to touch files outside your scope, note it in your progress file and wait.
    7. Never use --force on git operations.
    8. Follow command safety rules from references/conventions.md (Command Safety) and the agent guidance in [Agent Command Construction](#agent-command-construction). Use Read/Grep/Glob/Edit tools for file operations; keep Bash commands simple — no `&&`, no `2>/dev/null`, no `$()`, one operation per call.

    Per-task commit recipe:
      a. Use the Write tool to create `.ccpm/initiatives/<initiative>/<epic>/<N>-commit-msg.txt`.
         - Subject: `Issue #<N>: <description>`
         - Blank line, then body describing what changed.
         - Trailer: `Co-Authored-By: <name> <email>` (per project convention).
         The task-id-scoped path means parallel agents on different task IDs cannot collide.
      b. Invoke the coordinator (single Bash tool call):

         bash <skill-root>/references/scripts/ccpm-commit-task-work.sh <initiative> <epic> <N> --message-file .ccpm/initiatives/<initiative>/<epic>/<N>-commit-msg.txt --push -- <your-stream-files>

         The script validates the subject format, applies the FR-3 staging matrix internally (code paths always; progress file when `CCPM_TRACKED=true`), runs the FR-8 atomic commit, removes the message file on success (preserves it on failure for diagnosis), and — with `--push` — invokes the push coordinator gated on `ONLINE`. See [Coordinator Scripts](conventions.md#coordinator-scripts).
      c. Read the script's status output:
         - `committed: Issue #<N>: <description>` — commit produced.
         - `no changes to commit (subject: …)` — no diff (unusual mid-stream; investigate).
         - `pushed: initiative/<initiative-name>` — push succeeded (when --push and ONLINE=true).
         - `skipped: offline` — push skipped (ONLINE=false).
         - Non-zero exit + stderr — surface to the orchestrator.

    Progress comment on GitHub (gated on `SYNC_ENABLED`, which the orchestrator has determined):
      - When `SYNC_ENABLED=true`: `gh issue comment <N> --body "<short status>"` to post incremental progress.
      - When `SYNC_ENABLED=false`: skip the `gh` call silently.

    Complete your stream's work and mark status: completed when done.
```

Streams with unmet dependencies are queued — launch them as their dependencies complete.

**Step 4 — Assign on GitHub** (only when `SYNC_ENABLED=true`):
```bash
gh issue edit <N> --add-assignee @me --add-label "in-progress"
```

**Step 5 — Create execution status file** at `.ccpm/initiatives/<initiative>/<epic>/updates/<N>/execution.md`:
```markdown
## Active Streams
- Stream A: <name> — Started <time>
- Stream B: <name> — Started <time>

## Queued
- Stream C: <name> — Waiting on Stream A

## Completed
(none yet)
```

**Output:**
```
✅ Started work on issue #<N>

Launched N agents:
  Stream A: <name> ✓ Started
  Stream B: <name> ✓ Started
  Stream C: <name> ⏸ Waiting (depends on A)

Monitor: check progress in .ccpm/initiatives/<initiative>/<epic>/updates/<N>/
Sync updates: "sync issue <N>"
```

---

## Starting an Initiative

**Trigger**: User wants to launch parallel agents across all ready tasks in an initiative.

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- **Mode detection**: After the root check, run the canonical [Mode-Detection Preflight](conventions.md#mode-detection-preflight) so `CCPM_TRACKED`, `METHOD_DIR`, `METHOD_TRACKED`, `WORKTREE_ACTIVE`, `ONLINE`, and `SYNC_ENABLED` are available for the rest of this phase. The flags are passed through to every agent launched below.
- Verify `.ccpm/initiatives/<name>/<name>.md` exists.
- Check for uncommitted changes: `git status --porcelain` — block if dirty.
- Verify initiative branch exists and is checked out: `git branch --show-current` should match `initiative/<name>`.

### Process

**Step 1 — Collect all task files** across all epics in the initiative. Glob for `.ccpm/initiatives/<name>/*/[0-9]*.md` to gather tasks from every epic directory. Parse each task's frontmatter for `status`, `depends_on`, `parallel`, and `conflicts_with`.

**Worktree resolution**: use `WORKTREE_ACTIVE` from the mode detection. If `true`, resolve the worktree path (`../<repo-basename>-<initiative-name>/`) and pass it to all agent launches as the working directory. If `false`, agents work in the project root on the initiative branch.

**Step 2 — Build unified dependency graph.** Treat all tasks as one pool regardless of which epic they belong to. Task IDs in `depends_on` and `conflicts_with` can reference tasks from any epic within the initiative. Detect circular dependencies across the full graph — if found: "❌ Circular dependency detected: `<details>`"

**Step 3 — Categorize tasks:**
- Ready: status=open, no unmet depends_on, no unresolved conflicts_with
- Blocked: has unmet depends_on or unresolved conflicts_with
- In Progress: already has an execution file
- Complete: status=closed

**Step 4 — Analyze any ready tasks** that don't have an analysis file yet (run issue analysis inline).

**Step 5 — Launch agents** for all ready tasks following the same per-issue agent launch pattern above. Each agent uses the per-task commit recipe documented in [Starting an Issue](#starting-an-issue) Step 3 — the agent and coordinator share one recipe (no separate agent path), and the task-id-scoped message-file path keeps parallel agents on different task IDs from colliding.

**Step 6 — Create/update** `.ccpm/initiatives/<name>/execution-status.md` with all active agents and queued tasks, organized by epic for readability.

**Step 7 — As agents complete**, check if blocked tasks are now unblocked and launch those agents.

---

## Agent Command Construction

Agents must follow the Command Safety rules from `references/conventions.md`. In addition, these rules govern how agents construct commands during task execution:

**Use native tools for file operations:**
- Read files with the Read tool, not `cat`, `head`, or `tail` in Bash
- Search file content with the Grep tool, not `grep` or `rg` in Bash
- Find files with the Glob tool, not `find` or `ls` in Bash
- Edit files with the Edit tool, not `sed` or `awk` in Bash

**Keep Bash commands simple and single-purpose:**
- One operation per Bash call. Don't chain with `&&` or `;`.
- Don't redirect stderr: no `2>&1`, no `2>/dev/null`. If a command might fail, run it and check the result in the next step.
- Don't use command substitution (`$()` or backticks) in Bash tool calls.
- Don't write inline scripts (Python, jq, Ruby) in Bash tool calls. If parsing is needed, create a script file first or use a native tool.

**Match project permission patterns:** Simple commands like `go test ./...`, `npm test`, `cargo build` match project-level permission patterns (e.g., `Bash(go test:*)`). The user approves the pattern once and all subsequent calls pass. Complex commands like `cd dir && go test 2>&1 | head -50` don't match any pattern and require individual approval every time.

**Examples:**

| Don't | Do |
|-------|-----|
| `cd frontend && npm test` | `npm test --prefix frontend` (or run from the correct directory) |
| `go list -u -m all 2>&1 \| grep '\['` | Run `go list -u -m all`, then use the Grep tool on the output |
| `cat config.json \| python3 -c "import json..."` | Use the Read tool to read config.json, then process the content directly |
| `git status && git diff && git log` | Three separate Bash tool calls |

---

## Agent Coordination Rules

When multiple agents work on the initiative branch simultaneously:

- Each agent works only on files in its assigned stream scope.
- Agents commit and push via `ccpm-commit-task-work.sh` (with `--push`) per the recipe in [Starting an Issue](#starting-an-issue) Step 3. The task-id-scoped message-file path keeps parallel agents on disjoint task IDs from colliding.
- Before modifying a shared file, check its modification state with the Read tool — if another agent has it modified, wait and pull first.
- Agents sync via commits before starting new file work. Pull-rebase is performed by the coordinator script when needed (see the script's retry-on-non-fast-forward behaviour). When offline, the script silently skips the pull.
- `gh issue comment` for progress is gated solely on `SYNC_ENABLED=true`; the agent emits the call directly (the `gh` wrapper effort is deferred). The push step is encapsulated in the coordinator and gated solely on `ONLINE`. The two flags do not cross-gate each other (see [Independent gating](conventions.md#independent-gating)).
- Conflicts are never auto-resolved — agents report them and pause.
- No `--force` flags ever.

Shared files that commonly need coordination (types, config, package.json) should be handled by one designated stream; others pull after that commit.
