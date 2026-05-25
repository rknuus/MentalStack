# Review — GitHub PR Review Loop

This phase covers the GitHub-based code review loop for an initiative: push the initiative branch to GitHub for PR review, then iteratively fetch and address review comments via `gh` until the user is satisfied and merges separately.

CCPM data (initiatives, epics, tasks) is **not** synced to GitHub Issues. Only the branch and the PR conversation cross the boundary.

---

## Tooling Rules — read first

The review loop is implemented entirely by coordinator scripts under `<skill-root>/references/scripts/`. The only commands the agent runs are these scripts and the file-edit tools needed to apply review fixes (`Read`, `Edit`, `Write`).

**Do NOT run direct `gh ...` or `git ...` commands while executing this phase.** In particular:

- ❌ Do not use `gh pr view`, `gh pr list`, `gh pr create`, or any other `gh pr ...` command. The fetch coordinator resolves the PR for the initiative branch internally; `gh pr create` is intentionally out of scope (the user creates the PR manually).
- ❌ Do not use `gh api` directly. The fetch and reply coordinators wrap every `gh api` call needed.
- ❌ Do not run `git remote -v`, `git ls-remote`, `git fetch`, `git pull`, `git branch --list`, `git push`, or `git commit`. The push coordinator validates the local branch and the remote, performs the push, and surfaces a single `review-push: ready` status when the branch is on GitHub.
- ❌ Do not "verify" before invoking a coordinator. Coordinators own their preflight: missing remote, missing branch, unauthenticated `gh`, missing PR — each surfaces a single-line, actionable error.

The **only** raw shell calls in this phase are:

- `git rev-parse --show-toplevel` — once, to confirm the agent's cwd is the project root.
- The five coordinator invocations listed below (push for review, fetch comments, reply on a thread, commit a fix, push again).

If a coordinator emits an error, surface it to the user verbatim and stop. Do not work around it with raw `git`/`gh`.

### Coordinator surface

| Action | Coordinator |
|---|---|
| Push initiative branch for PR review | `ccpm-push-for-review.sh <initiative>` |
| Fetch unresolved PR review threads | `ccpm-fetch-review-comments.sh <initiative>` |
| Reply on a review thread | `ccpm-reply-review-thread.sh <initiative> <root-comment-id> <body-file>` |
| Commit a review-comment fix | `ccpm-commit-review-fix.sh <initiative> --message-file <path> -- <code-path…>` |

`ccpm-gh-verify.sh` runs implicitly inside the push/fetch/reply coordinators; the agent never invokes it directly.

---

## Prerequisites

The review-loop coordinators require `gh` to be installed and authenticated against the repository's host:

```bash
gh auth login
```

The coordinators run a `gh` preflight and abort with an actionable message if `gh` is missing, unauthenticated, or unable to resolve the current repository. There is no `SYNC_ENABLED` gate here — review is invoked explicitly by the user, so a missing `gh` is a hard error, not a silent skip.

---

## Push for Review

**Trigger**: User wants to push an implemented initiative's branch to GitHub so a PR review can be performed. Example phrases:

- "push the `<name>` initiative for review"
- "push `<name>` for review"
- "@ccpm push <name> for review"

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- That is the entire phase-doc preflight. The push coordinator handles initiative-file existence, local-branch existence, remote configuration, and `gh` authentication.

### Process

**Step 1 — Push the branch via the coordinator:**

```bash
bash <skill-root>/references/scripts/ccpm-push-for-review.sh <name>
```

On success the coordinator emits `review-push: ready`. On any failure (no local branch, no `origin` remote, `gh` not authenticated, push skipped because offline) it exits non-zero with a single-line message — surface that message and stop. Do not run any `git` or `gh` command to "diagnose."

**Step 2 — User opens or refreshes the PR.**

This step is **manual**: the user opens the PR in the GitHub UI (or runs `gh pr create` themselves). CCPM does not create PRs as part of this initiative.

If a PR for `initiative/<name>` already exists, no further action is needed — the new commits are already on the open PR.

### Post-completion

```
✅ Branch pushed for review: initiative/<name>

  Status: review-push: ready
  Next:
    - Open or refresh the PR on GitHub (manual)
    - Once review comments arrive, run: address review comments for <name>
```

### Error handling

Surface the coordinator's exit message verbatim. Common cases:
- `gh CLI not installed` / `gh not authenticated` / `unable to resolve current repository` — fix `gh` setup with the suggested command.
- `local branch not found` — implement the initiative first.
- `no 'origin' remote configured` — add a remote with `git remote add origin <url>`.
- `branch was not pushed (ONLINE=false)` — restore connectivity and retry.

In every case: **do not** run `git remote -v`, `git ls-remote`, or any other diagnostic command. The error is already actionable.

---

## Address Review Comments

**Trigger**: User has left review comments on the initiative's PR and wants TCCPM to address them. Example phrases:

- "address review comments for `<name>`"
- "address the review comments"
- "@ccpm address review comments for <name>"

### Preflight
- **Root check**: Run `git rev-parse --show-toplevel` and confirm the working directory is the project root. If not, `cd` to the root before proceeding.
- That is the entire phase-doc preflight. The fetch and reply coordinators handle initiative-file existence, PR resolution for the initiative branch, and `gh` authentication.

### Process

**Step 1 — Fetch open review comments:**

```bash
bash <skill-root>/references/scripts/ccpm-fetch-review-comments.sh <name> > /tmp/review-comments.json
```

The coordinator filters out resolved threads (using GraphQL `isResolved`) and emits a JSON array of unresolved threads, each with: `thread_id`, `root_comment_id`, `path`, `line`, and a `comments` array.

If the array is empty:

```
✅ No open review comments for initiative <name>.
```

Stop — there is nothing to address.

If the coordinator exits non-zero (e.g. "no PR found for branch initiative/<name>; push and create one first"), surface that message and stop. **Do not** invoke `gh pr list`, `gh pr view`, or any `gh api` call to investigate further.

**Step 2 — For each unresolved thread, address it:**

Iterate over `/tmp/review-comments.json` (use `Read` and `jq` via the file content; the JSON is small). For each thread:

1. **Read the referenced location** with the `Read` tool — open the file at `path`, find the relevant region (use `line` as the anchor; comments may apply to a range, so read context above and below).

2. **Read the comment thread** — the `comments` array may contain multiple comments (the original and any follow-ups). The most recent comment is typically the one to address; earlier ones are context.

3. **Plan and apply the fix** — make the code edit using the `Edit` / `Write` tools that addresses the feedback. Stay within the file/region the comment refers to unless the comment explicitly asks for cross-file changes.

4. **Write a reply body to a temp file** describing what was changed and why. Reading reply bodies from a file (rather than inline) keeps multi-line and special-character bodies safe:

   ```bash
   cat > /tmp/reply-body.md <<'EOF'
   Renamed `foo` → `bar` and updated all call sites in <files>.
   The behaviour is unchanged; only the identifier changed.
   EOF
   ```

5. **Post the reply via the coordinator:**

   ```bash
   bash <skill-root>/references/scripts/ccpm-reply-review-thread.sh <name> <root_comment_id> /tmp/reply-body.md
   ```

   `<root_comment_id>` comes from the JSON entry. The coordinator does **not** mark the thread resolved — the user reviews the change and decides whether to resolve it.

6. **Commit the fix via the coordinator.** Write a commit-message file (subject must start with `Address review`), then invoke the commit coordinator:

   ```bash
   cat > /tmp/review-fix-msg.txt <<'EOF'
   Address review comment on <path>:<line>

   <one-line summary of the change>
   EOF
   bash <skill-root>/references/scripts/ccpm-commit-review-fix.sh <name> \
        --message-file /tmp/review-fix-msg.txt \
        -- <code-path…>
   ```

   The coordinator validates the subject, runs the atomic commit recipe, and removes the message file on success. **Do not** run `git add`, `git commit`, or `git status` directly.

   Use one commit per addressed comment when fixes are independent; combine when a single change addresses multiple comments and call that out in the message.

**Step 3 — Push the new commits for re-review:**

```bash
bash <skill-root>/references/scripts/ccpm-push-for-review.sh <name>
```

This re-pushes the branch so the new commits show up on the existing PR.

### Post-completion

```
✅ Addressed N review comments for initiative <name>.

  Threads replied to: N (none marked resolved — user decides)
  Commits pushed:     M
  Branch:             initiative/<name>

Re-review on the PR. When satisfied: merge the <name> initiative.
```

### Error handling
- Any coordinator failure: surface the message verbatim and stop. Do not retry with raw `gh`/`git` commands.
- An edit conflicts with previously addressed feedback: surface the conflict and stop — never auto-resolve.
- A reply post fails after the code edit committed: the commit stays on the branch; the user can re-run the address-comments command to retry the reply for that thread (the fetch coordinator returns the thread again as long as it is unresolved).

---

## Loop Shape

The full review loop, end-to-end:

1. User: implement initiative locally on `initiative/<name>` (regular CCPM work).
2. User: `push the <name> initiative for review` → branch pushed.
3. User: open / refresh the PR on GitHub manually.
4. User: leave review comments on the PR.
5. User: `address review comments for <name>` → fixes applied, threads replied, branch re-pushed.
6. User: re-review on GitHub. If more comments, return to step 5.
7. When satisfied, user: `merge the <name> initiative` (existing flow; not part of this phase).
