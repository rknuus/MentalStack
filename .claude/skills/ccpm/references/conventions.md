# Conventions — File Formats, Paths & Rules

Read this before doing any file operations across all phases.

---

## Directory Structure

```
.ccpm/
├── settings.yml                     # Project-level CCPM settings (optional)
├── initiatives/
│   ├── <name>.md                    # Initiative document
│   └── <name>/                      # Epics for this initiative
│       └── <epic-name>/             # Epic directory
│           ├── epic.md              # Epic document
│           ├── <N>.md               # Task files (N = global ID)
│           └── updates/             # Work-in-progress updates
│               └── <issue_N>/
│                   └── stream-A.md  # Per-agent progress
├── archive/                         # Completed initiatives (moved on merge)
│   └── <name>/                      # Archived initiative (same structure as initiatives/)
│       ├── <name>.md                # Initiative document
│       └── <epic-name>/             # Epic directory (preserved)
│           ├── epic.md
│           └── <N>.md
└── next-id                          # Global task ID counter
```

---

## Root Anchoring

All `.ccpm/` paths are relative to the git project root (`git rev-parse --show-toplevel`). To prevent `.ccpm/` from being created in a subdirectory:

**In bash scripts**: Every script that accesses `.ccpm/` must `cd` to the git root as its first executable statement:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
```

**In sourced libraries** (e.g., `paths-lib.sh`): Do not `cd` — the caller is responsible for being at the root before sourcing.

**In phase Preflight sections** (mandatory first step): Before any `.ccpm/` access, run `git rev-parse --show-toplevel` and confirm the output matches the current working directory. If it does not, `cd` to the project root before proceeding. Do not use `$()` — run the command directly and read the output.

---

## Command Authorization

An explicit `@ccpm` command is authorization to proceed. Do not ask "shall I proceed?" or "approve this plan?" when the user has already given a command.

- **Proceed by default**: `@ccpm decompose` means create the task files. `@ccpm initiative-go` means run all phases. Show the result, not a preview.
- **Report, don't ask**: After completing work, report what was done (e.g., "Created 5 tasks for epic: auth"). Do not present a plan and wait for approval.
- **Prompt only when destructive or ambiguous**: Overwriting existing files, merging with incomplete epics, or failing tests warrant a confirmation. Routine creation does not.

---

## Command Safety

Keep Bash tool calls simple and single-purpose so each one matches a permission pattern (e.g., `Bash(go test:*)`) and can be approved once. The permission monitor flags shell metacharacters — avoid them.

| Rule | Do | Don't |
|---|---|---|
| **Prefer native tools over Bash** | Edit tool for file changes, Read tool for reading, Grep tool for searching content, Glob tool for finding files | `sed`, `cat`/`head`/`tail`, `grep` in Bash, `find`/`ls` in Bash |
| **One command per Bash call** | Separate Bash tool calls for each command | `git checkout main && git pull origin main` |
| **No stderr redirection** | Run the command plain; handle errors in the next step. For optional operations, note "skip on failure" in surrounding instruction text | `git remote get-url origin 2>/dev/null` |
| **No command substitution in Bash calls** | Run the command in one Bash call, reference the output in the next | `` `cmd` `` or `$(cmd)` inside a Bash tool call |
| **Simple, single-purpose commands** | `go test ./...` | `cd dir && go test 2>&1 \| head` |

**Scripts are exempt**: The monitor only sees the top-level Bash tool call (e.g., `bash references/scripts/status.sh`), not commands executed within the script.

---

## Task ID Counter

The file `.ccpm/next-id` contains the next available globally unique task ID as a plain integer. Before creating any task files, read this value. After creating all tasks, update it to the next unused value.

Read `.ccpm/next-id` (via the Read tool) to get the next available ID. After creating all tasks, write the next unused value:

```bash
echo "<new_next_id>" > .ccpm/next-id
```

---

## Frontmatter Schemas

### Initiative (.ccpm/initiatives/<name>.md)
```yaml
---
name: <feature-name>        # kebab-case, matches filename
description: <one-liner>    # used in lists and summaries
status: backlog | in-progress | complete | cancelled
created: <ISO 8601>         # date -u +"%Y-%m-%dT%H:%M:%SZ"
worktree: false              # optional; true = use git worktree for this initiative
cancelled: <ISO 8601>       # set on cancel (optional)
cancel_reason: <text>        # why it was cancelled (optional)
---
```

### Epic (.ccpm/initiatives/<initiative>/<name>/epic.md)
```yaml
---
name: <feature-name>
status: backlog | in-progress | completed
created: <ISO 8601>
updated: <ISO 8601>
progress: 0%                # recalculated when tasks close
initiative: .ccpm/initiatives/<initiative>/<name>.md
depends_on: []              # list of epic names that must complete first
github: https://github.com/<owner>/<repo>/issues/<N>  # set on sync
worktree_path:               # optional; path to initiative worktree (derived)
---
```

### Task (.ccpm/initiatives/<initiative>/<name>/<N>.md)
```yaml
---
name: <Task Title>
status: open | in-progress | closed
created: <ISO 8601>
updated: <ISO 8601>
github: https://github.com/<owner>/<repo>/issues/<N>  # set on sync
depends_on: []              # issue numbers this must wait for
parallel: true              # can run concurrently with non-conflicting tasks
conflicts_with: []          # issue numbers that touch the same files
worktree_path:               # optional; inherited from epic
---
```

### Progress (.ccpm/initiatives/<initiative>/<name>/updates/<N>/progress.md)
```yaml
---
issue: <N>
started: <ISO 8601>
last_sync: <ISO 8601>
completion: 0%
---
```

---

## Datetime Rule

Always get real current datetime from the system — never use placeholder text:
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

---

## Frontmatter Update Pattern

When updating a single frontmatter field in an existing file:

Use the Edit tool to replace the frontmatter line. Match the full line (e.g., `status: backlog`) and replace with the new value (e.g., `status: in-progress`).

When stripping frontmatter to get body content for GitHub:

Use the Read tool with `offset` to skip frontmatter lines, then use the body content directly.

---

## Project-Mode Detection

CCPM phase recipes branch on six runtime flags that describe the project's git/sync posture. Each flag has a single canonical source of truth: a `.ccpm/settings.yml` override (when present) wins over auto-detection. The implementation lives in `references/scripts/ccpm-detect-mode.sh`, invoked as a fresh bash subprocess per phase action. The user-facing settings keys (`ccpm_tracked`, `method_dir`, `method_tracked`, `github_sync`) are documented in `templates/README.md` under "Project-Mode Settings".

### Mode-Detection Preflight

Every phase entry-point (the recipes in `plan.md`, `initiative.md`, `structure.md`, `sync.md`, `execute.md`) runs the mode-detection routine once, up front, before any branching, staging, or sync decision.

The detection script supports two output formats. Pick **one** based on how the rest of the phase consumes the flags. Each form is composed of simple Bash tool calls — no `$(...)` or `<(...)` substitution, so Claude Code's risky-command monitor stays quiet.

**Form A — JSON read (preferred when the agent reasons about flags directly).** One Bash tool call; the agent reads the JSON output from the tool result and uses it to decide what to run next. No shell variables; no temp file; no second step.

```bash
bash <skill-root>/references/scripts/ccpm-detect-mode.sh --json <initiative>
# → {"ccpm_tracked":true,"method_dir":".pm","method_tracked":true,"worktree_active":false,"online":true,"sync_enabled":true}
```

**Form B — file-sourced flags (when subsequent inline shell commands need the flags as env vars).** Three simple Bash tool calls: write the KEY=VALUE output to a temp file, source it, delete the file.

```bash
bash <skill-root>/references/scripts/ccpm-detect-mode.sh <initiative> > /tmp/ccpm-mode-<initiative>.env
source /tmp/ccpm-mode-<initiative>.env
rm /tmp/ccpm-mode-<initiative>.env
# CCPM_TRACKED, METHOD_DIR, METHOD_TRACKED, WORKTREE_ACTIVE, ONLINE, SYNC_ENABLED now in env
```

**Hard rule: no `eval $(…)` wrappers.** The shorter `eval "$(bash …)"` form would do the same job in one line, but `$(...)` inside a Bash tool call trips the risky-command monitor and forces a per-call approval prompt. Use Form A or Form B; never compose detection invocations through `$(…)` or `<(…)` from agent-facing shell. Inside coordinator scripts (Epic 2 and beyond) — which run as `bash <coordinator>.sh …` — `$()` is fine because it executes inside the script body, not in the agent's Bash tool call.

**cwd contract**: All CCPM recipes in this skill assume the agent's current working directory is the git project root. The "Root check" Preflight bullet at the top of every phase doc (`plan.md`, `initiative.md`, `structure.md`, `sync.md`, `execute.md`) enforces this — it runs `git rev-parse --show-toplevel` and `cd`s once if cwd is elsewhere, before any other step. Because of that contract, the `bash …`, `source …`, and `git …` lines in this recipe (and in every phase recipe that follows) use plain relative paths and **must not** be wrapped in `cd <project> && bash …` or `cd <project> && git …`. Compound `cd && <git|bash|source>` invocations trip the risky-command monitor and force an approval prompt on every call; the Preflight cwd check exists precisely so they are never needed. If the rare case arises that the agent genuinely cannot `cd` to project root (e.g. running git from a tool that fixes cwd elsewhere), use `git -C <project-root> …` instead of a `cd && git` wrapper — see `command-safety.md` for the full rationale.

The six flags resolved by both forms are:

- `CCPM_TRACKED` — `true` when `.ccpm/` is tracked by git, `false` when ignored.
- `METHOD_DIR` — relative path to the architect directory (ACCPM only); empty in TCCPM or when no `*.method` directory exists.
- `METHOD_TRACKED` — `true` when `${METHOD_DIR}/` is tracked; forced `false` when `METHOD_DIR` is empty.
- `WORKTREE_ACTIVE` — `true` when this initiative has a sibling worktree at `../<repo-basename>-<initiative>/` and the initiative frontmatter requests it.
- `ONLINE` — `true` when `origin` is reachable (probed via `git ls-remote --exit-code origin HEAD`).
- `SYNC_ENABLED` — `true` when `gh` is on PATH and `gh auth status` succeeds.

**Fresh-process contract**: each `bash ccpm-detect-mode.sh` invocation re-probes the live state — there is no in-process cache to invalidate. State changes between phase actions (e.g. `gh auth login` mid-session, a freshly created worktree) are picked up automatically by the next invocation. Phase docs invoke detection once per phase action; they do not assume any state carries over from a prior phase.

### Flag resolution

| Flag | Setting override | Auto-detection (when override absent) |
|---|---|---|
| `CCPM_TRACKED` | `ccpm_tracked: true\|false` | `git check-ignore -q .ccpm/` exit 1 → `true`; exit 0 → `false` |
| `METHOD_DIR` | `method_dir: <relative path>` | Glob `*.method` (directory only) at repo root; 0 matches → empty; 1 match → that path; multiple matches → fail-fast (override required) |
| `METHOD_TRACKED` | `method_tracked: true\|false` | `git check-ignore -q "$METHOD_DIR/"` exit 1 → `true`; forced `false` when `METHOD_DIR` is empty |
| `WORKTREE_ACTIVE` | `worktree: true\|false` (initiative frontmatter — controls intent) | Initiative frontmatter `worktree: true` AND `git worktree list` shows a sibling worktree at `../<repo-basename>-<initiative-name>/` |
| `ONLINE` | (no override — environmental) | `git remote get-url origin` succeeds AND `git ls-remote --exit-code origin HEAD` succeeds |
| `SYNC_ENABLED` | `github_sync: true\|false` | `gh` is on PATH AND `gh auth status` succeeds |

### `ONLINE` and `SYNC_ENABLED` are independent

The two flags do not cross-gate each other. A project can be `ONLINE=true, SYNC_ENABLED=false` (git remote reachable but `gh auth` expired), or `ONLINE=false, SYNC_ENABLED=true` (the user runs `git push`/`pull` manually but lets CCPM call `gh issue ...`). Each flag is auto-detected and overridable on its own — `SYNC_ENABLED`'s auto-detection deliberately does not probe the network, since `gh`'s own calls fail loudly if connectivity is missing and that is the right place for that error to surface.

### When to use overrides

- `ccpm_tracked: false` — open-source fork that keeps `.ccpm/` out of upstream history.
- `method_dir: <path>` — multiple `*.method` directories exist; auto-detection would fail fast.
- `method_tracked: false` — architect directory exists but should not be staged in CCPM-driven commits.
- `github_sync: true` — pin sync on so transient `gh` auth blips do not flip behaviour mid-session.
- `github_sync: false` — fork where `gh` is globally authenticated but should not be used for this repo.

### Implementation reference

The detection routine is `bash references/scripts/ccpm-detect-mode.sh <initiative-name>`. By default it prints six `KEY=VALUE` lines (suitable for redirect-and-source via Form B above); pass `--json` before the initiative name for a single-line JSON object (suitable for Form A). Each invocation is a fresh bash subprocess — there is no in-process cache. See the script's header comment for full semantics. The internal helper `ccpm-settings.sh` is also available standalone (`bash ccpm-settings.sh <key>` or `--json`) for direct access to a single `.ccpm/settings.yml` value.

The flags computed here drive the FR-3 staging matrix that the [Coordinator Scripts](#coordinator-scripts) implement internally — that section documents the contract each script honours and how `CCPM_TRACKED` (and, in ACCPM, `METHOD_TRACKED`) gates pathspec assembly.

---

## Coordinator Scripts

CCPM phase actions are implemented by a suite of **coordinator scripts** under `references/scripts/`. Each script encapsulates a single CCPM phase action — branch creation, file commits, push, merge, cancellation — behind a stable, allowlist-friendly invocation:

```
bash <skill-root>/references/scripts/ccpm-<action>.sh [args]
```

Phase recipes invoke these scripts. They never compose `git commit`/`git add`/`git push`/`git checkout` invocations directly — the FR-3 staging matrix, the FR-8 atomic-commit protocol, the `ONLINE`/`SYNC_ENABLED` gating, and the worktree cleanup ordering all live *inside* the scripts and are verified by their unit tests. The agent's role contracts to: invoke script → read status → reason about next phase step.

### The action surface

| Script | Inputs | Action |
|---|---|---|
| `ccpm-create-branch.sh` | `<initiative>` | Checkout `main`, pull (gated on `ONLINE`), create `initiative/<name>` (or attach a sibling worktree at `../<repo-basename>-<name>/` when frontmatter says `worktree: true`), push (gated on `ONLINE`). Existing branch → switch to it. |
| `ccpm-commit-initiative.sh` | `<initiative>` | Write the per-commit message file (subject `Initiative: <name>`, body from frontmatter description), run the FR-8 commit, remove the message file. Skip when `CCPM_TRACKED=false`. |
| `ccpm-commit-epic.sh` | `<initiative> <epic>` `[--summary <line>]` | Same shape; subject `Epic: <epic>` (or `Epic: <epic> — <summary>`); pathspec is the epic's `epic.md`. |
| `ccpm-commit-tasks.sh` | `<initiative> <epic>` | Subject `Epic: <epic> — N tasks`; pathspec is the `[0-9]*.md` glob in the epic dir, plus `.ccpm/next-id` when tracked. |
| `ccpm-commit-task-work.sh` | `<initiative> <epic> <task-id> --message-file <path> [--push] -- <code-path…>` | Per-agent code commit. Agent provides the `Issue #<N>: …` message file; coordinator validates the subject, assembles pathspecs (code + optional updates dir), runs the commit, optionally pushes. Parallel-safe via per-task message files. |
| `ccpm-push-branch.sh` | `<initiative>` | `git push origin initiative/<name>`. Gated on `ONLINE`; silent skip when off. |
| `ccpm-merge-initiative.sh` | `<initiative> [--force-incomplete]` | Rebase initiative onto `main` (worktree-aware), `git merge --ff-only`, remove worktree, force-delete branch, push delete (gated on `ONLINE`), archive `.ccpm/initiatives/<name>` to `.ccpm/archive/<name>`. |
| `ccpm-cancel-initiative.sh` | `<initiative> [--archive] [--reason <text>]` | Same cleanup order as merge (worktree-remove BEFORE branch-D), no merge step, then either `rm -rf` or archive with `cancelled: true` injected into frontmatter. |

Every coordinator accepts an optional `--json` flag that switches its status output from plain text to a single-line `{"status":"…"}` object — useful when a calling script wants to parse the result. Default is plain text.

### Output and exit-status conventions

- **Plain text** (default): one or more lines of human-readable status to stdout. Any error context goes to stderr.
- **`--json`** mode: one or more `{"status":"<line>"}` objects on stdout, one per status emission.
- **Exit codes**: `0` success (including soft no-ops like empty diffs and gating-off skips), `1` validation/operation error, `2` mode-detection error (e.g. `METHOD_DIR` multi-match per FR-1).

### Invariants the scripts implement

These were the recipe rules in earlier versions of CCPM. They are now properties of the coordinator scripts, verified by `tests/test-coord-*.sh` and the per-script unit tests:

1. **FR-3 staging matrix.** `CCPM_TRACKED` gates `.ccpm/` paths; `METHOD_TRACKED` gates `${METHOD_DIR}/` paths (ACCPM only — added by the agentify pipeline). The matrix is no longer agent-visible. Phase recipes do not compose pathspecs; they invoke a coordinator and the coordinator decides which paths to capture.

2. **FR-8 atomic commit protocol.** Each commit-creating coordinator implements `Write message file → git commit -F <msg> -- <pathspec…> → rm <msg>`. The internal helper `coord_commit` (in `lib/coordinator-lib.sh`) registers intent-to-add for new files, runs `git commit` once, and removes the message file unconditionally. The pathspec form bypasses the shared index, so two coordinator scripts running in parallel on disjoint pathspecs cannot cross-contaminate each other's commits.

3. **Independent gating.** `ONLINE` gates remote operations (`git push`, `git pull`); `SYNC_ENABLED` gates `gh` operations. Neither implies the other. Scripts skip silently when their gate is off; they do not cascade.

4. **Worktree cleanup ordering.** `merge-initiative` and `cancel-initiative` always `git worktree remove` BEFORE `git branch -D` (FR-4). Branch deletion fails outright when the branch is checked out in another worktree, so the order is load-bearing.

5. **Hard rule: no broad pathspecs.** No coordinator runs `git commit -- .ccpm/` or `git commit -- .`. Every pathspec is either a specific file or a glob that cannot match `*-commit-msg.txt` (e.g. the task-file glob `[0-9]*.md`). The unconditional post-commit `rm` of the message file is the second line of defence. This rule is enforced by reading the script source — and by the per-script unit tests asserting exact pathspec content captured by the resulting commit.

6. **Single-line merge messages stay inline.** The two merge-style commits (`Merge initiative: <name>`, `Merge epic: <name>`) are produced via `git merge -m "<…>"` inside `ccpm-merge-initiative.sh`. They do not use a message file — single-line messages don't need one, and inline `-m` plays cleanly with `git merge --ff-only`.

### Permission allowlist guidance

A consumer project's settings need only one CCPM-scoped Bash entry to permit every coordinator invocation:

```
Bash(bash .claude/skills/ccpm/references/scripts/*.sh *)
```

The `Write(.ccpm/**)` permission (already in the global allow list) covers the agent-side message-file writes for `ccpm-commit-task-work.sh`. Narrow `rm` permissions for the `*-commit-msg.txt` patterns are still needed at the project tier (see `templates/README.md` Permissions section) because coordinator scripts run `rm` directly. No `git commit:*`, `git checkout:*`, `git branch:*`, etc. permissions are needed any longer for CCPM phase actions — those operations happen inside the coordinator subprocesses.

`gh issue …` calls remain inline in `sync.md` for now (encapsulation deferred to a later effort), so the existing `Bash(gh:*)` permission is still required for sync.

### Internal helper

`references/scripts/lib/coordinator-lib.sh` is sourced by every coordinator script. It provides `coord_init`, `coord_msg_path`, `coord_commit`, `coord_push_branch`, and `coord_status`. Agents never invoke this file directly; it is internal infrastructure.

---

## GitHub Operations

### Repository Safety Check (run before any write operation)

Run `git remote get-url origin` as a plain command. If no remote exists, the command will fail — check the output and proceed accordingly.

If the URL contains `automazeio/ccpm`, stop: "Cannot write to the CCPM template repository." Otherwise, extract the `OWNER/REPO` slug from the URL (strip `github.com[:/]` prefix and `.git` suffix) and use it as `REPO` in subsequent `gh` commands.

### Authentication
Don't pre-check authentication. Run the `gh` command and handle failure:
```bash
gh <command> || echo "❌ GitHub CLI failed. Run: gh auth login"
```

### Getting Issue Numbers

Use the Grep tool to search for the `github:` field in the task file, then extract the issue number from the matched line.

---

## Git / Branch Conventions

These rules are the canonical contract for every git invocation in CCPM phase recipes. The per-phase recipes in `plan.md`, `initiative.md`, `structure.md`, `sync.md`, and `execute.md` reference them rather than re-prescribing branch flow inline.

- **One branch per initiative**: `initiative/<name>`.
- **Commit format**: `Issue #<N>: <description>`. Merge commits use `Merge initiative: <name>` or `Merge epic: <name>` (single-line, inline `git merge -m "<…>"` is fine — see [Coordinator Scripts](#coordinator-scripts) for everything else).
- **Never use `--force`** in any git operation. No `--force-with-lease`, no `push --force`, no `rebase --force`. CCPM has no recipe that requires rewriting published history.

### Branch creation

Always start branches from an up-to-date `main`. The `git pull` step is gated solely on `ONLINE`; the checkout steps are unconditional.

```bash
git checkout main
```
```bash
# only when ONLINE=true
git pull origin main
```
```bash
git checkout -b initiative/<name>
```

When `ONLINE=false`, skip the `git pull` line silently and proceed with whatever `main` already holds locally — no warning, no error.

### Push / pull cadence

`ONLINE` is the **sole gate** on every `git push` and `git pull` invocation in CCPM recipes. There are no other conditions: a recipe either runs the push/pull when `ONLINE=true` or skips it silently when `ONLINE=false`.

- `git push -u origin initiative/<name>` runs at first sync only, gated on `ONLINE=true`.
- Subsequent `git push` of task commits runs only when `ONLINE=true`.
- `git pull origin main` runs only at branch creation and at "merge initiative" rebase time, gated on `ONLINE=true`. Mid-initiative pulls are out of scope.

### `gh` cadence

`SYNC_ENABLED` is the **sole gate** on every `gh` invocation (issue create, label, comment, close, etc.). There are no other conditions: a recipe either runs the `gh` call when `SYNC_ENABLED=true` or skips it silently when `SYNC_ENABLED=false`.

### Independent gating

`ONLINE` and `SYNC_ENABLED` do **not** cross-gate each other. Both of these combinations are legitimate and must be supported by every recipe:

- `ONLINE=true, SYNC_ENABLED=false` — git remote reachable but `gh` auth unavailable; recipes run `git push`/`pull` and skip `gh`.
- `ONLINE=false, SYNC_ENABLED=true` — `gh` authenticated (and reaches GitHub through its own API path) but the user pushes/pulls manually; recipes run `gh issue ...` and skip `git push`/`pull`.

A recipe never says "skip `gh` because `ONLINE=false`" or "skip `git push` because `SYNC_ENABLED=false`". Each gate stands alone.

### Merge initiative

The "merge initiative" step is the **only** place a rebase onto `main` is permitted across the entire CCPM workflow. The sequence:

1. `git checkout initiative/<name>`
2. `git pull origin main` (only when `ONLINE=true`) — refresh the local `main` ref first via the branch-creation pattern above
3. `git rebase main` — rebase the initiative branch onto latest `main`
4. `git checkout main`
5. `git merge --ff-only initiative/<name>` — fast-forward only; the rebase in step 3 guarantees this is always possible

No other phase rebases. `git pull --rebase` outside of the merge-initiative recipe is forbidden.

## Worktree Conventions

When `worktree: true` is set on an initiative, a git worktree is created as a sibling directory:

- **Path**: `../<repo-basename>-<initiative-name>/` (sibling to project root)
- **Created**: during initiative decompose or via `@ccpm worktree enable <name>`
- **Scope**: one worktree per initiative — all epics share it
- **Creation**: `git worktree add ../<repo-basename>-<name> initiative/<name>` (no remote interaction needed; unconditional with respect to `ONLINE`)

Worktrees are optional. Initiatives without `worktree: true` use plain branches (existing behavior).

### Cleanup at merge or cancel

The cleanup recipe is **single-valued** — same commands at merge time and at cancel time, in the same order:

1. `git worktree remove ../<repo-basename>-<initiative-name>`
2. `git branch -D initiative/<name>`

The `git worktree remove` step **must** run before `git branch -D`. `git branch -D` of a branch that is checked out in another worktree fails outright, so worktree-first ordering is mandatory.

Branch deletion uses `-D` (force), not `-d`. The rationale is the same in both flows but for slightly different reasons:

- **At merge time**, the branch's commits are already on `main` — preserved by the preceding `git merge --ff-only` step in the merge-initiative recipe — so loss is impossible. Empirically, `-d` is also unreliable right after `git worktree remove`: lingering ref-state from the removed worktree can cause `-d` to refuse a branch that is, in fact, fully merged. `-D` sidesteps that intermittent failure.
- **At cancel time**, the branch is unmerged by design. `-d` would refuse outright on policy grounds; `-D` is mandatory.

Using the same `-D` form in both flows keeps the cleanup recipe single-valued — no "or", no "try `-d` and fall back to `-D`". One command, one outcome.

---

## Naming Conventions

- Feature names: kebab-case, lowercase, letters/numbers/hyphens, starts with a letter
- Task files before sync: use globally unique IDs from `.ccpm/next-id` (e.g., `42.md`, `43.md`)
- Task files after sync: renamed to GitHub issue number (e.g., `1234.md`)
- Labels applied on sync: `epic`, `epic:<name>`, `feature` (for epics); `task`, `epic:<name>` (for tasks)

---

## Epic Progress Calculation

Use the Glob tool to find task files matching `.ccpm/initiatives/<initiative>/<name>/[0-9]*.md`, then use the Grep tool to find which of those contain `status: closed`. Calculate progress as `closed * 100 / total`.

Update epic frontmatter when any task closes.

---

## Local-Only Mode

CCPM works without GitHub. If `gh` CLI is not installed or not authenticated:
- All GitHub sync operations are skipped
- Task files in `.ccpm/` are the source of truth
- Git branches still provide epic isolation
- `git push/pull` operations fail silently (local branches only)

To enable GitHub integration later, install `gh` and run `bash references/scripts/init.sh`.
