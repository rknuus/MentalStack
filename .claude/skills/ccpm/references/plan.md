# Plan — Capture Requirements

This phase turns an idea into a structured Initiative, then converts the Initiative into a technical epic ready for decomposition.

---

## Writing an Initiative

**Trigger**: User wants to plan a new feature, product requirement, or area of work.

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- **Mode detection**: After the root check, run the canonical [Mode-Detection Preflight](conventions.md#mode-detection-preflight) so `CCPM_TRACKED`, `METHOD_DIR`, `METHOD_TRACKED`, `WORKTREE_ACTIVE`, `ONLINE`, and `SYNC_ENABLED` are available for the rest of this phase.
- Check if `.ccpm/initiatives/<name>/<name>.md` already exists — if so, confirm overwrite before proceeding.
- Ensure `.ccpm/initiatives/<name>/` directory exists; create it if not.
- Feature name must be kebab-case (lowercase, letters/numbers/hyphens, starts with a letter). If not: "❌ Feature name must be kebab-case. Example: user-auth, payment-v2"
- **Worktree default**: Check if `.ccpm/settings.yml` exists and contains `worktree: true`. This is the default for new initiatives. The user can override in their request with keywords: "with worktree" / "in a worktree" / "using worktree" → set worktree to `true`; "without worktree" / "no worktree" → set worktree to `false`.

### Process

Conduct a genuine brainstorming session before writing anything. Ask the user:
- What problem does this solve?
- Who are the users affected?
- What does success look like?
- What's explicitly out of scope?
- What are the constraints (tech, time, resources)?

Probe for domain concepts and their correctness properties:
- **Identifiers**: Key entities, uniqueness scope, reuse rules
- **State**: Valid states, allowed transitions, source of truth
- **Ordering**: Ordered collections, invariants after mutations
- **Consistency**: Multiple representations, disagreement handling
- **Concurrency**: Concurrent modifications, conflict resolution
- **Idempotency**: Which operations must be safe to retry

Then write `.ccpm/initiatives/<name>/<name>.md` with this frontmatter and structure:

```markdown
---
name: <feature-name>
description: <one-line summary>
status: backlog
worktree: false
created: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
---

# Initiative: <feature-name>

## Executive Summary
## Problem Statement
## User Stories
## Functional Requirements
## Non-Functional Requirements
## Success Criteria
## Constraints & Assumptions
## Out of Scope
## Dependencies
```

**Quality gates before saving:**
- No placeholder text in any section
- User stories include acceptance criteria
- Success criteria are measurable
- Out of scope is explicitly listed

**After creation**: Confirm "✅ Initiative created" and list the file as a bare relative path on its own line (no backticks or formatting — terminals make bare paths Cmd+Clickable):

```
✅ Initiative created

.ccpm/initiatives/<name>/<name>.md
```

If `worktree: true`, append to the confirmation: "Worktree will be created during decomposition at `../<repo-basename>-<name>/`."

**Commit the initiative file** — invoke the coordinator script:

```bash
bash <skill-root>/references/scripts/ccpm-commit-initiative.sh <name>
```

The script runs mode detection internally, gates on `CCPM_TRACKED`, builds the commit message from the initiative file's `description:` frontmatter, runs the FR-8 atomic commit, and prints a single-line status. Expected status outputs:

- `committed: Initiative: <name>` — commit produced.
- `CCPM_TRACKED=false; initiative file not committed (working tree only)` — `.ccpm/` is gitignored; the file stays in the working tree (downstream phases reference it from disk).
- `no changes to commit (subject: Initiative: <name>)` — re-running with no diff (idempotent).
- Non-zero exit + error to stderr — surface to the user.

The first push of the initiative branch happens at sync time per [Push / pull cadence](conventions.md#push--pull-cadence); no push is needed here.

**Recommend next step**: Assess the initiative you just wrote and recommend one of three paths. Use these proxy measures:
- **User story count**: how many distinct user stories
- **Functional requirement count**: how many requirements
- **Scope boundary complexity**: how large/detailed is "Out of Scope"
- **Cross-subsystem spread**: does the work span multiple distinct technical areas
- **External dependencies**: how many external systems or teams involved
- **Deliverable count**: do success criteria imply one deliverable or several distinct ones

Based on the assessment, recommend one tier:

| Tier | When to recommend | Command |
|------|-------------------|---------|
| **initiative-go** | Very small, super-clear scope. 1-2 user stories, single deliverable, no cross-subsystem complexity. May produce as few as 1 task. | `@ccpm initiative-go <name>` |
| **Single-epic parse** | Medium scope. Cohesive single deliverable but needs task-level planning and review. 3-5 user stories, moderate complexity. | `parse the <name> initiative` |
| **Multi-epic decompose** | Large scope. Multiple distinct deliverables or subsystems, many user stories, complex dependencies between areas. | `decompose the <name> initiative into epics` |

Present the recommendation concisely — one line of assessment, then the options:

```
**Recommendation**: <one-line assessment, e.g., "Small, focused initiative — single deliverable with clear scope">

  ➤ @ccpm initiative-go <name>                       ← recommended
    parse the <name> initiative
    decompose the <name> initiative into epics
    let's revise the <name> initiative
```

Always list all four options (the three tiers plus "revise"). Mark the recommended one with "← recommended". The user decides which to use.

---

## Parsing an Initiative into a Technical Epic

**Trigger**: User wants to convert an existing Initiative into a technical implementation plan.

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- **Mode detection**: After the root check, run the canonical [Mode-Detection Preflight](conventions.md#mode-detection-preflight) so `CCPM_TRACKED`, `METHOD_DIR`, `METHOD_TRACKED`, `WORKTREE_ACTIVE`, `ONLINE`, and `SYNC_ENABLED` are available for the rest of this phase.
- Verify `.ccpm/initiatives/<name>/<name>.md` exists with valid frontmatter (name, description, status, created).
- Check if `.ccpm/initiatives/<name>/<epic-name>/epic.md` already exists — confirm overwrite if so.

### Process

Read the Initiative fully, then produce `.ccpm/initiatives/<name>/<epic-name>/epic.md`:

```markdown
---
name: <feature-name>
status: backlog
created: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
progress: 0%
initiative: .ccpm/initiatives/<name>/<name>.md
github: (will be set on sync)
---

# Epic: <feature-name>

## Overview
## Architecture Decisions
## Technical Approach
### Frontend Components
### Backend Services
### Infrastructure
## Implementation Strategy
## Task Breakdown Preview
## Dependencies
## Success Criteria (Technical)
## Estimated Effort
```

**Key constraints:**
- Aim for ≤10 tasks total — prefer simplicity over completeness.
- Look for ways to leverage existing functionality before creating new code.
- Identify parallelization opportunities in the task breakdown preview.

**After creation**: Confirm "✅ Epic created" and list the file as a bare relative path on its own line:

```
✅ Epic created

.ccpm/initiatives/<name>/<epic-name>/epic.md

Ready to decompose into tasks? Say: decompose the <epic-name> epic
```

**Commit the epic file** — invoke the coordinator script:

```bash
bash <skill-root>/references/scripts/ccpm-commit-epic.sh <name> <epic-name>
```

The script runs mode detection internally, gates on `CCPM_TRACKED`, runs the FR-8 atomic commit, and prints a single-line status. Expected status outputs:

- `committed: Epic: <epic-name>` — commit produced.
- `CCPM_TRACKED=false; epic file not committed (working tree only)` — `.ccpm/` is gitignored.
- `no changes to commit (subject: Epic: <epic-name>)` — idempotent re-run.
- Non-zero exit + error to stderr — surface to the user.

See [Coordinator Scripts](conventions.md#coordinator-scripts) for the full action surface and invariants. The first push happens at sync time per [Push / pull cadence](conventions.md#push--pull-cadence); no push is needed here.

**Next steps to suggest:**
- "Decompose into tasks: decompose the <epic-name> epic"
- "Review or revise: let's refine the <epic-name> epic"

---

## Editing an Initiative or Epic

Read the file first, make targeted edits preserving all frontmatter. Update the `updated` frontmatter field with current datetime.
