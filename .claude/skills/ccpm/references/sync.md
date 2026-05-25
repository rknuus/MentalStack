# Sync — Push to GitHub & Track Progress

This phase covers pushing local epics/tasks to GitHub as issues, syncing progress as comments, and closing issues when work is done.

---

## Preflight (Mode Detection)

Every entry-point in this file runs the **Mode-Detection Preflight** from `conventions.md` (see [Project-Mode Detection](conventions.md#project-mode-detection)) before any branching, push, or `gh` invocation. After it returns, `ONLINE` and `SYNC_ENABLED` are in the environment and gate the rest of the recipe.

The two flags are **independent** — they do not cross-gate each other (see [Git / Branch Conventions → Independent gating](conventions.md#independent-gating)):

- Every branch push in this file goes through `ccpm-push-branch.sh`, which gates **solely** on `ONLINE` internally.
- Every `gh` invocation in this file is gated **solely** on `SYNC_ENABLED` via inline conditionals (the `gh` wrapper effort is deferred — those calls remain raw for now).

### Gate-combination truth table

| `ONLINE` | `SYNC_ENABLED` | Behaviour |
|---|---|---|
| `true` | `true` | Fully online — branch is pushed, GitHub issues are created/updated/closed. |
| `true` | `false` | Branch is pushed; no GitHub issues created or updated. Local task IDs (from `.ccpm/next-id`) remain authoritative; task files keep their local-ID filenames. |
| `false` | `true` | No branch push. `gh issue ...` calls run against the existing remote — assumes the user has pushed `initiative/<name>` manually. |
| `false` | `false` | Fully offline — sync is a no-op for git and GitHub alike; only local frontmatter updates run. |

Skipped steps are silent: each emits a single `info:` log line and continues. None raises an error.

---

## Repository Safety Check

**Always run this before any GitHub write operation** (i.e. when `SYNC_ENABLED=true`).

Run and read the output:
```bash
git remote get-url origin
```

If no remote is configured, this will fail — treat the rest of the recipe as if `SYNC_ENABLED=false` (skip every `gh` call with the standard `info:` line).

If the URL contains `automazeio/ccpm`, stop: "Cannot sync to the CCPM template repository." Otherwise, extract the `OWNER/REPO` slug from the URL (strip `github.com[:/]` prefix and `.git` suffix) and use it as `REPO` in subsequent `gh` commands.

---

## Epic Sync — Push Epic + Tasks to GitHub

**Trigger**: User wants to push a local epic and its tasks to GitHub as issues.

### Preflight
- Run the Mode-Detection Preflight (see top of this file).
- Verify `.ccpm/initiatives/<initiative>/<name>/epic.md` exists.
- Verify task files exist — if none: "❌ No tasks to sync. Decompose the epic first."

### Process

**Step 0 — Push the initiative branch:**

```bash
bash <skill-root>/references/scripts/ccpm-push-branch.sh <name>
```

The coordinator gates push on `ONLINE` internally — emits `pushed: initiative/<name>` when online, `skipped: offline` when off. When `ONLINE=false` but `SYNC_ENABLED=true`, the subsequent `gh` calls assume the user pushed the branch manually. CCPM does not verify this — `gh` will surface its own error if the remote ref is missing. See [Coordinator Scripts](conventions.md#coordinator-scripts).

**Step 1 — Create epic issue (gated on `SYNC_ENABLED`):**

Strip frontmatter from epic.md:
```bash
sed '1,/^---$/d; 1,/^---$/d' .ccpm/initiatives/<initiative>/<name>/epic.md > /tmp/epic-body.md
```

Then, if `SYNC_ENABLED=true`, create the issue and read the output to get the issue number:
```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  gh issue create \
    --repo "<REPO>" \
    --title "Epic: <name>" \
    --body-file /tmp/epic-body.md \
    --label "epic,epic:<name>,feature" \
    --json number -q .number
else
  printf 'info: skipping gh issue create (epic) — SYNC_ENABLED=false\n'
fi
```

When `SYNC_ENABLED=false`, skip Steps 1–3 entirely (no epic issue, no task issues, no rename). Steps 4–5 still run against local IDs.

**Step 2 — Create task sub-issues (gated on `SYNC_ENABLED`):**

Check if `gh-sub-issue` extension is available:
```bash
if [ "$SYNC_ENABLED" = "true" ] && gh extension list | grep -q "yahsan2/gh-sub-issue"; then
  use_subissues=true
fi
```

For <5 tasks: create sequentially.
For ≥5 tasks: use parallel Task agents (3-4 tasks per batch).

Per task — strip frontmatter:
```bash
sed '1,/^---$/d; 1,/^---$/d' <task_file> > /tmp/task-body.md
```

Then, when `SYNC_ENABLED=true`, create the issue and read the output to get the issue number:
```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  gh issue create \
    --repo "<REPO>" \
    --title "<task_name>" \
    --body-file /tmp/task-body.md \
    --label "task,epic:<name>" \
    --json number -q .number
else
  printf 'info: skipping gh issue create (task) — SYNC_ENABLED=false\n'
fi
```
If using sub-issues: `gh sub-issue create --parent <epic_number> ...` (also gated on `SYNC_ENABLED=true`).

**Step 3 — Rename task files and update references (only when `SYNC_ENABLED=true`):**

After all issues are created, rename `<id>.md` → `<issue_number>.md` and update all `depends_on`/`conflicts_with` arrays to use real issue numbers (not local IDs).

Build the old-to-new ID mapping. For each task file, use the Edit tool with `replace_all: true` to replace every occurrence of `<old_id>` with `<new_num>` in the file content. Then rename the file:
```bash
mv <old_id>.md <new_num>.md
```

When `SYNC_ENABLED=false`, skip this step entirely — local task filenames keep their `.ccpm/next-id`-allocated values and are the authoritative IDs going forward.

**Step 4 — Update frontmatter:**

Get the current timestamp:
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

Then use the Edit tool to update fields in epic.md and each task file:
- `updated: <timestamp>` — always.
- `github: https://github.com/<REPO>/issues/<number>` — only when `SYNC_ENABLED=true`. When `SYNC_ENABLED=false`, leave the `github:` field at its placeholder (`(will be set on sync)`).

**Step 5 — Create github-mapping.md (only when `SYNC_ENABLED=true`):**
```markdown
# GitHub Issue Mapping
Epic: #<N> - https://github.com/<repo>/issues/<N>
Tasks:
- #<N>: <title> - https://github.com/<repo>/issues/<N>
Synced: <datetime>
```

When `SYNC_ENABLED=false`, skip this step — there are no GitHub IDs to map.

**Output:**
```
✅ Synced epic <name> to GitHub
  Epic: #<N>
  Tasks: N sub-issues
  Next: "start working on issue <N>" or "start the <name> initiative"
```

When `SYNC_ENABLED=false`, the output reads:
```
✅ Local sync complete for epic <name>
  Tasks: N (local IDs retained)
  Next: "start working on task <local_id>" or "start the <name> initiative"
```

---

## Issue Sync — Post Progress to GitHub

**Trigger**: User wants to sync local development progress to a GitHub issue as a comment.

### Preflight
- Run the Mode-Detection Preflight (see top of this file).
- If `SYNC_ENABLED=true`: verify the issue exists with `gh issue view <N> --json state`.
- Check `.ccpm/initiatives/<initiative>/<epic>/updates/<N>/` exists with a `progress.md` file.
- Check `last_sync` in progress.md — if synced <5 minutes ago, confirm before proceeding.

### Process

Gather updates from `.ccpm/initiatives/<initiative>/<epic>/updates/<N>/` (progress.md, notes.md, commits.md).

**Push task commits:**

```bash
bash <skill-root>/references/scripts/ccpm-push-branch.sh <name>
```

**Post the progress comment (gated on `SYNC_ENABLED`):**

```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  gh issue comment <N> --body-file /tmp/update-comment.md
else
  printf 'info: skipping gh issue comment — SYNC_ENABLED=false\n'
fi
```

Comment format:
```markdown
## 🔄 Progress Update - <date>

### ✅ Completed Work
### 🔄 In Progress
### 📝 Technical Notes
### 📊 Acceptance Criteria Status
### 🚀 Next Steps
### ⚠️ Blockers

---
*Progress: N% | Synced at <timestamp>*
```

After posting (or after the local-only update): refresh `last_sync` in progress.md frontmatter and `updated` in the task file.

Add sync marker to local files to prevent duplicate comments:
```markdown
<!-- SYNCED: <datetime> -->
```

When `SYNC_ENABLED=false`, the sync marker still records the local-only sync timestamp; subsequent runs honour the same 5-minute debounce.

---

## Closing an Issue

**Trigger**: User marks a task complete.

### Process

1. Run the Mode-Detection Preflight (see top of this file).
2. Find the local task file (`.ccpm/initiatives/<initiative>/<epic>/<N>.md`).
3. Update frontmatter: `status: closed`, `updated: <now>`.
4. Push the close-out commit:
```bash
bash <skill-root>/references/scripts/ccpm-push-branch.sh <name>
```
5. Post completion comment and close the issue (gated on `SYNC_ENABLED`):
```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  echo "✅ Task completed — all acceptance criteria met." | gh issue comment <N> --body-file -
  gh issue close <N>
else
  printf 'info: skipping gh issue comment/close — SYNC_ENABLED=false\n'
fi
```
6. Check off the task in the epic issue body (gated on `SYNC_ENABLED`):
```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  gh issue view <epic_N> --json body -q .body > /tmp/epic-body.md
  # Use the Edit tool to replace `- [ ] #<N>` with `- [x] #<N>` in /tmp/epic-body.md.
  gh issue edit <epic_N> --body-file /tmp/epic-body.md
else
  printf 'info: skipping gh issue edit (epic body) — SYNC_ENABLED=false\n'
fi
```
7. Recalculate and update epic progress: `progress = closed_tasks / total_tasks * 100`. Always runs against local task files; not gated.

---

## Reporting a Bug Against a Completed Issue

**Trigger**: User finds a bug while testing a completed or in-progress issue — e.g. "found a bug in issue 42", "email validation is broken, came up while testing issue 42".

The workflow should stay automated: create a linked bug task without losing context from the original issue.

### Process

0. Run the Mode-Detection Preflight (see top of this file).

**Step 1 — Read the original issue for context (gated on `SYNC_ENABLED`):**
```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  gh issue view <original_N> --json title,body,labels
else
  printf 'info: skipping gh issue view (original) — SYNC_ENABLED=false\n'
fi
```
Also read the local task file if it exists: `.ccpm/initiatives/<initiative>/<epic>/<original_N>.md`. The local file is always available regardless of `SYNC_ENABLED`.

**Step 2 — Create a local bug task file:**

```markdown
---
name: Bug: <short description>
status: open
created: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
updated: <same>
github: (will be set on sync)
depends_on: []
parallel: false
conflicts_with: []
bug_for: <original_N>
---

# Bug: <short description>

## Context
Found while working on / testing issue #<original_N>: <original title>

## Description
<what's broken>

## Steps to Reproduce
<steps>

## Expected vs Actual
- Expected:
- Actual:

## Acceptance Criteria
- [ ] Bug is fixed
- [ ] Original issue #<original_N> behaviour is unaffected

## Effort Estimate
- Size: XS/S
```

Save to `.ccpm/initiatives/<initiative>/<epic>/bug-<original_N>-<slug>.md`. When `SYNC_ENABLED=false`, allocate the next local ID from `.ccpm/next-id` for the eventual filename.

**Step 3 — Create a linked GitHub issue (gated on `SYNC_ENABLED`):**
```bash
if [ "$SYNC_ENABLED" = "true" ]; then
  gh issue create \
    --repo "<REPO>" \
    --title "Bug: <short description>" \
    --body-file /tmp/bug-body.md \
    --label "bug,epic:<epic_name>" \
    --json number -q .number
else
  printf 'info: skipping gh issue create (bug) — SYNC_ENABLED=false\n'
fi
```

The issue body should open with `Fixes / follow-up to #<original_N>` so GitHub auto-links them.

**Step 4 — Update the local file** with the GitHub issue number and rename to `<new_N>.md` (only when `SYNC_ENABLED=true`). When `SYNC_ENABLED=false`, keep the local ID from `.ccpm/next-id` as the filename and leave the `github:` field at its placeholder.

**Output (`SYNC_ENABLED=true`):**
```
✅ Bug issue created: #<new_N> — "Bug: <short description>"
  Linked to: #<original_N>
  Epic: <epic_name>

Start fixing it: "start working on issue <new_N>"
```

**Output (`SYNC_ENABLED=false`):**
```
✅ Bug task created locally: <local_id> — "Bug: <short description>"
  Linked to: #<original_N>
  Epic: <epic_name>

Start fixing it: "start working on task <local_id>"
```

---

## Local-Only Mode

"Local-only" describes any state where one or both of `ONLINE` and `SYNC_ENABLED` are `false`. The mode is **not** binary — there are three distinct local-only quadrants, each with its own behaviour (see the truth table at the top of this file):

- **`ONLINE=true, SYNC_ENABLED=false`** — git remote is reachable but `gh` is unavailable (or disabled via `github_sync: false`). The branch is pushed; no GitHub issues are created or touched. Task files in `.ccpm/` keep their local IDs and are the source of truth.
- **`ONLINE=false, SYNC_ENABLED=true`** — `gh` works (it has its own auth/network path) but git pushes are off. Issues are created/updated against the existing remote; the user is responsible for `git push`/`pull` of the branch itself.
- **`ONLINE=false, SYNC_ENABLED=false`** — fully offline. Sync is a no-op for git and GitHub; only local frontmatter updates run.

In all three cases, local task files in `.ccpm/` remain authoritative for whatever the missing channel cannot record. To re-enable a missing channel later: install/authenticate `gh` (for `SYNC_ENABLED`), restore network connectivity (for `ONLINE`), and run `bash references/scripts/init.sh` if first-time setup is required. Then re-run the phase — the next `bash ccpm-detect-mode.sh` invocation re-probes live state automatically (each invocation is a fresh process; no cache to invalidate).
