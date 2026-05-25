---
name: ccpm
description: "CCPM - spec-driven project management: Initiative → Epic → GitHub Issues → parallel agents → shipped code. Always activate when the user prefixes a message with '@ccpm'. Use this skill for anything in the software delivery lifecycle: writing an initiative ('write an initiative for X', 'create an initiative for X', 'new initiative for X'), decomposing an initiative into multiple epics ('decompose the X initiative into epics', 'break X into epics'), start all epics ('start all epics for X', 'run all epics'), merge initiative ('merge the X initiative'), cancel initiative ('cancel initiative X', 'abandon X'), add epic to initiative ('add epic Y to X'), parsing an initiative into an epic, decomposing an epic into tasks, syncing to GitHub ('sync the X epic', 'push tasks to github'), starting work on an issue ('start working on issue N', 'let's work on issue N'), analyzing parallel work streams, running standups ('standup', 'run the standup'), checking status ('what's next', 'what's blocked', 'what are we working on'), closing issues, merging an epic, pushing an initiative branch for GitHub PR review ('push the X initiative for review', 'push X for review'), or addressing review comments on the PR ('address review comments for X', 'address the review comments'). Use ccpm when the user mentions initiatives, epics, tasks, or shipping features with traceability. Do NOT use for: debugging code, writing tests, reviewing PRs, generic planning without delivery context, or raw GitHub issue/PR operations."
---

# CCPM - Claude Code Project Manager

A spec-driven development workflow: Initiative → Epic → GitHub Issues → Parallel Agents → Shipped Code.

## Core Philosophy

Requirements live in files, not heads. Every feature starts as an Initiative, becomes a technical epic, decomposes into GitHub issues, and gets executed by parallel agents with full traceability.

CCPM works in local-only mode without GitHub. GitHub integration is optional — install and authenticate `gh` CLI to enable it.

## File Conventions

Before doing anything, read `references/conventions.md` for path standards, frontmatter schemas, and GitHub operation rules. These apply to all phases.

## The Five Phases

### 1. Plan — Capture requirements
**When**: User wants to define a new feature, product requirement, or scope of work.
**Read**: `references/plan.md`
**Covers**: Writing Initiatives through guided brainstorming, converting Initiatives to technical epics.

### 1b. Initiative — Multi-epic decomposition
**When**: User has an initiative that needs multiple epics, or wants to run all epics at once.
**Read**: `references/initiative.md`
**Covers**: Decomposing initiatives into multiple epics, initiative-go (one-step), epic-start-all (sequential), initiative merging, initiative cancellation, adding epics to running initiatives, worktree management.

### 2. Structure — Break it down
**When**: An epic exists and needs to be decomposed into concrete tasks.
**Read**: `references/structure.md`
**Covers**: Epic decomposition into numbered task files with dependencies and parallelization.

### 3. Sync — Push to GitHub
**When**: Local epic/tasks need to become GitHub issues, progress needs to be posted as comments, or a bug is found and needs a linked issue created.
**Read**: `references/sync.md`
**Covers**: Epic sync (epic + tasks → GitHub issues), issue sync (progress comments), closing issues/epics, bug reporting against completed issues.

### 4. Execute — Start building
**When**: User wants to start working on one or more GitHub issues with parallel agents.
**Read**: `references/execute.md`
**Covers**: Issue analysis (parallel work stream identification), launching parallel agents, agent coordination.

### 5. Track — Know where things stand
**When**: User asks for status, standup report, what's blocked, what's next, or needs to validate state.
**Read**: `references/track.md`
**Covers**: Status, standup, search, in-progress, next priority, blocked items, validation.

---

## Context Management
**When**: User wants to create, update, or load project context.
**Read**: `references/context.md`
**Covers**: Creating baseline context, refreshing with recent changes, loading context in new sessions.

## GitHub PR Review Loop
**When**: An initiative has been implemented and the user wants a GitHub PR review before merging — or wants TCCPM to address review comments left on the PR.
**Read**: `references/review.md`
**Covers**: Pushing the initiative branch for review, fetching unresolved review comments via `gh`, addressing each comment with a code edit + thread reply, and re-pushing for re-review. Initiative-level only. Initiatives, epics, and tasks are **not** synced to GitHub Issues — only the branch and the PR conversation cross. Requires `gh` to be installed and authenticated (`gh auth login`).

## Command Safety
**When**: User wants to reduce permission prompts for non-CCPM commands (builds, tests, linters).
**Read**: `references/command-safety.md`
**Covers**: Recommended `~/.claude/CLAUDE.md` additions, per-project command patterns, language-specific examples.

---

## Script-First Rule

For deterministic operations — anything that reads and reports without needing reasoning — always run the bash script directly rather than doing the work manually:

| What the user wants | Script to run |
|---|---|
| Project status | `bash references/scripts/status.sh` |
| Standup report | `bash references/scripts/standup.sh` |
| List all epics | `bash references/scripts/epic-list.sh` |
| Show epic details | `bash references/scripts/epic-show.sh <name>` |
| Epic status | `bash references/scripts/epic-status.sh <name>` |
| List Initiatives | `bash references/scripts/initiative-list.sh` |
| Initiative status | `bash references/scripts/initiative-status.sh` |
| Search issues/tasks | `bash references/scripts/search.sh <query>` |
| What's in progress | `bash references/scripts/in-progress.sh` |
| What's next | `bash references/scripts/next.sh` |
| What's blocked | `bash references/scripts/blocked.sh` |
| Validate project state | `bash references/scripts/validate.sh` |

Use the LLM for work that requires reasoning: writing Initiatives, analyzing parallelism, launching agents, synthesizing updates.

---

## Explicit Invocation

Prefix any message with `@ccpm` to explicitly route it to CCPM, bypassing intent detection:

```
@ccpm plan sorting archived tasks last to first
@ccpm what's the status?
@ccpm decompose the auth epic into tasks
```

The `@ccpm` prefix guarantees CCPM handles the request, even for phrases that might otherwise trigger other tools (e.g., planning mode).

---

## Quick Reference

```
Plan a feature:     "create an initiative for X" or "@ccpm plan X"
Parse to epic:      "turn the X initiative into an epic"
Decompose:          "break down the X epic into tasks"
Sync to GitHub:     "push the X epic to GitHub"
Start an issue:     "start working on issue 42"
Check status:       "what's our status" / "standup"
What's next:        "what should I work on next"
Merge epic:         "merge the X epic"
Break into epics:   "decompose the X initiative into epics"
Start all epics:    "start all epics for X" or "run all epics"
Merge initiative:   "merge the X initiative"
Cancel initiative:  "cancel initiative X" / "abandon X"
Add epic:           "add epic Y to X" / "new epic Y for X"
Enable worktree:  "worktree enable X" or "@ccpm worktree enable X"
Report a bug:       "found a bug in issue 42" / "testing issue 42 revealed X"
Push for review:    "push the X initiative for review"           (requires gh)
Address comments:   "address review comments for X"               (requires gh)
Create context:     "create context" or "set up context"
Update context:     "update context" or "refresh context"
Load context:       "prime context" or "load context"
```
