# Structure — Break Down an Epic

This phase converts a technical epic into concrete, numbered task files with dependency and parallelization metadata.

---

## Epic Decomposition

**Trigger**: User wants to break an epic into actionable tasks.

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- **Mode detection**: After the root check, run the canonical [Mode-Detection Preflight](conventions.md#mode-detection-preflight) so `CCPM_TRACKED`, `METHOD_DIR`, `METHOD_TRACKED`, `WORKTREE_ACTIVE`, `ONLINE`, and `SYNC_ENABLED` are available for the rest of this phase.
- Verify `.ccpm/initiatives/<initiative>/<name>/epic.md` exists with valid frontmatter.
- If task files already exist in the epic directory, list them and confirm deletion before recreating.
- If epic status is "completed", warn the user before proceeding.

### Process

Read the epic fully. Analyze for parallelism — which pieces of work can happen simultaneously without file conflicts?

**Worktree propagation**: Read the parent initiative's `worktree:` field (from `.ccpm/initiatives/<initiative>/<initiative>.md`). If `worktree: true`, resolve the worktree path (`../<repo-basename>-<initiative-name>/`) and include `worktree_path:` in the epic and task frontmatter templates below.

**Task types to consider:**
- Setup: environment, scaffolding, dependencies
- Data: models, schemas, migrations
- API: endpoints, services, integration
- UI: components, pages, styling
- Tests: unit, integration, e2e
- Docs: README, API docs, changelogs

**Task ID assignment:**
Read the next available ID from `.ccpm/next-id`. Assign each task its ID. After creating all tasks, update `.ccpm/next-id` to the next unused value.

**Parallelization strategy by epic size:**
- Small (<5 tasks): create sequentially
- Medium (5–10 tasks): batch into 2–3 groups, spawn parallel Task agents
- Large (>10 tasks): analyze dependencies first, launch parallel agents (max 5 concurrent), create dependent tasks after prerequisites

For parallel creation, use the Task tool:
```yaml
Task:
  description: "Create task files batch N"
  subagent_type: "general-purpose"
  prompt: |
    Create task files for epic: <name>
    Tasks to create: [list 3-4 tasks]
    Save to: .ccpm/initiatives/<initiative>/<name>/<id>.md (using IDs from .ccpm/next-id)
    Follow the task file format exactly.
    Return: list of files created.
```

### Task File Format

```markdown
---
name: <Task Title>
status: open
created: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
updated: <same as created>
github: (will be set on sync)
depends_on: []
parallel: true
conflicts_with: []
worktree_path:               # optional; inherited from epic
---

# Task: <Task Title>

## Description

## Acceptance Criteria
- [ ]

## Technical Details

## Dependencies

## Effort Estimate
- Size: XS/S/M/L/XL
- Hours: N

## Definition of Done
- [ ] Code implemented
- [ ] Tests written and passing
- [ ] Code reviewed
```

**Numbering**: use globally unique IDs from `.ccpm/next-id` (e.g., `42.md`, `43.md`). Tasks are renamed to GitHub issue numbers after sync — do not hard-code dependencies by filename, use the `depends_on` array.

### After Creating All Tasks

Append a summary to the epic file:

```markdown
## Tasks Created
- [ ] <id>.md - <Title> (parallel: true/false)
- [ ] <id>.md - <Title> (parallel: true/false)

Total tasks: N
Parallel tasks: N
Sequential tasks: N
Estimated total effort: N hours
```

**Commit the task files** — invoke the coordinator:

```bash
bash <skill-root>/references/scripts/ccpm-commit-tasks.sh <initiative> <name>
```

The script counts the task files for the commit subject (`Epic: <name> — N tasks`), assembles the pathspec list per the FR-3 staging matrix, runs the FR-8 atomic commit, and prints a single-line status. Expected status outputs:

- `committed: Epic: <name> — N tasks` — commit produced.
- `CCPM_TRACKED=false; task files not committed (working tree only)` — `.ccpm/` is gitignored.
- `no changes to commit (subject: Epic: <name> — N tasks)` — idempotent re-run.
- Non-zero exit + error to stderr — surface to the user.

See [Coordinator Scripts](conventions.md#coordinator-scripts).

**Optional push** — invoke the push coordinator:

```bash
bash <skill-root>/references/scripts/ccpm-push-branch.sh <initiative>
```

The script is gated solely on `ONLINE`; when offline it silently skips with status `skipped: offline`. Never uses `--force`.

**After completion**: Confirm "✅ Created N tasks for epic: <name>" and list all created task files as bare relative paths, one per line:

```
✅ Created N tasks for epic: <name>

.ccpm/initiatives/<initiative>/<name>/42.md
.ccpm/initiatives/<initiative>/<name>/43.md
.ccpm/initiatives/<initiative>/<name>/44.md

Ready to push to GitHub? Say: sync the <name> epic
```

**For multi-epic initiatives:** If this epic is part of a larger initiative with multiple epics, see `references/initiative.md` for coordinating across epics.

---

## Dependency Rules
- `depends_on` lists task numbers that must complete before this task can start.
- `parallel: true` means the task can run concurrently with others it doesn't conflict with.
- `conflicts_with` lists tasks that touch the same files — these cannot run in parallel.
- Circular dependencies are an error — check before finalizing.
