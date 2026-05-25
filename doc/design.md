# Mental-Stack for Claude Code — Design & Decision Record

A tool to track the nested "mental brackets" of complex work — the depth-first
path through a tree of tasks — while working primarily in Claude Code.

Status: **scaffold built and verified; awaiting one-time local setup.**

---

## 1. Requirements

The need: when doing complex work, you descend into sub-items, then sub-sub-items,
and eventually pop back up to continue where you left off. You want help tracking
which "brackets" are open and what to do next, ideally without leaving your normal
Claude workflow.

| # | Requirement | Notes |
|---|-------------|-------|
| R1 | Track a **tree of work** traversed depth-first | "Open brackets" = the path from the top level down to where you currently are; you also need to see *what's next* at each level. |
| R2 | Allow **non-linear navigation** | A strict push/pop call stack is only an approximation — human attention jumps sideways. Jumping to an arbitrary item must be a first-class operation. |
| R3 | **Commands usable from inside Claude**, not as separate shell commands | Including iterative refinement of upcoming items and explicit enter / exit of a sub-item. |
| R4 | State must **outlive a single Claude session** | It must survive across the *M* conversations spent on one project. |
| R5 | **Per-project isolation** | Work spans *N* projects. The state for one project must not bleed into the other *N−1*. |
| R6 | **Continuously visible** | Must stay in sight, not scroll out of view. Not acceptable: a "show current state" command (poor UX) or a separate web page to visit. |
| R7 | Work with the **Claude Code CLI**, the primary surface | Used inside a terminal multiplexer. |
| R8 | **Reuse existing open source** if a good fit exists | Prefer assembling over building. |

---

## 2. Key analysis

### 2.1 The model: call stack as a tree + cursor

The call-stack metaphor fits, but a bare LIFO of strings fails R1 and R2: it tells
you *where you are* but forgets the sibling brackets you haven't opened yet, and it
forbids sideways jumps. The model adopted is a **tree with a single movable cursor**:

- the path from root to cursor = the open brackets;
- the next open sibling = what's next when you exit/complete;
- a `goto` operation makes the non-linear jumps first-class (R2).

### 2.2 The surface trilemma

Three desired properties do **not** coexist in any single Claude facility today:

1. rendered **inside Claude's own UI**,
2. **pinned in sight** (never scrolls),
3. **live across the other Claude surfaces** in use.

- Inline rendering (MCP Apps, tool results) gives 1 + 3 but not 2 — inline content
  scrolls with the transcript.
- The **Artifacts side panel** (web/desktop) gives 1 + 2 but is conversation-local
  and **does not exist in the CLI** — disqualifying for R7.
- An **MCP server** is the only thing shared across surfaces (3) and the only place
  commands can live that are callable from inside Claude Code (R3) — but Claude has
  no pinned native renderer for its state.

**Decisive realisation:** in a terminal REPL, *nothing* can be pinned inside the
Claude Code surface itself — it is a single scrolling transcript. Therefore the
"in sight" view (R6) must live in a region *beside* Claude Code, not inside it.

The R5 clarification (state need only survive the *M* conversations per project,
not be shared live across simultaneous surfaces) removed the constraint that would
otherwise have forced complexity, and made per-cwd file persistence sufficient.

### 2.3 Existing projects evaluated (R8)

| Project | Verdict | Why |
|---------|---------|-----|
| `blizzy/mcp-task-manager` | **Reference only, do not fork** | Tasks held in an in-memory `Map` with no disk writes — state dies with the process and is globally shared (fails R4, R5). Its "tree" is a *dependency DAG*, not a containment hierarchy, and the schema is agent-oriented (definitions-of-done, uncertainty areas, etc.) — wrong ergonomics. Useful only as a tiny MIT reference for MCP tool registration. |
| Taskwarrior + MCP wrapper (`omniwaifu`, `acebaggins`) | **Viable "assemble" route, with model-bending** | Durable on-disk store (R4), contexts map to projects (R5), `start`/`stop` ≈ enter/exit, `taskwarrior-tui` as the viewer. But no true containment tree or ancestor-path cursor; nesting is approximated via dotted subprojects + `depends:`. Acceptable only if willing to bend the bracket model. |

### 2.4 Embedding vs. multiplexer

A custom PTY multiplexer (Rust `ratatui` + `tui-term`, or Python `Textual` + `pyte`)
would embed Claude Code in one region and pin the stack widget in a corner — the
closest thing to "embedded." Rejected as the first build because it re-creates and
amplifies the exact terminal fragility already experienced (VT/ANSI fidelity, resize
/ SIGWINCH propagation, key forwarding); `tui-term` is itself explicitly a
work-in-progress.

Chosen instead: a **zellij layout**. It inherits a battle-tested multiplexer's resize
handling, is more scriptable than tmux, and means only the small stack widget + MCP
server need to be built. This also directly addresses the prior instability of
running Claude inside tmux.

---

## 3. Decisions

- **D1 — Model:** tree + single cursor; open brackets = ancestor path; "next" = next
  open sibling. (R1, R2)
- **D2 — Commands live in an MCP server** (stdio), callable from inside Claude Code.
  (R3)
- **D3 — Persistence & isolation via a per-cwd state file** (`.mentalstack.json` in
  the project directory). Survives conversations; isolated per project automatically.
  (R4, R5)
- **D4 — The "in sight" view is a separate pane**, not inside Claude Code, because a
  terminal has nothing to pin to. (R6, R7)
- **D5 — zellij** provides the layout (Claude main pane + stack sidebar) rather than a
  hand-built terminal emulator. (R7)
- **D6 — Build, don't reuse**, for the core: existing projects either lack persistence
  (blizzy) or the bracket model (Taskwarrior). Build a small purpose-made server +
  viewer; keep blizzy as a scaffolding reference only. (R8)

---

## 4. Resulting architecture & plan

```
┌──────────────────────────────┬───────────────────┐
│                              │ 🧠 mental stack    │
│   Claude Code (claude)       │ (top level)        │
│   calls enter/exit/...       │ ▸ ship release [1] │
│                              │  ✓ cut RC     [2]  │
│                              │  ▸ sign       [3]  │ ← cursor
└──────────────────────────────┴───────────────────┘
        stack_view.py  ←reads—  .mentalstack.json  —writes→  stack_server.py
                                  (in the project cwd)
```

Two processes share one JSON file in the project's working directory. The MCP
server writes it atomically (`fsync` + `os.replace`); the viewer watches the file's
mtime and re-renders. No daemon, no socket.

**MCP tools** (the in-Claude command surface):

| Tool | Effect |
|------|--------|
| `enter(title)` | push a new child and descend (open a bracket) |
| `exit()` | step up to parent without closing |
| `complete(note?)` | close current, move to next open sibling / up |
| `add(title)` | queue a sibling at the current level; cursor stays |
| `goto(id)` | jump anywhere — descend into a planned item or move sideways |
| `refine(title)` | re-word the current item |
| `view()` | print path + children + what's next |

**Viewer:** a `rich` panel rendering the tree — open-bracket path in yellow, current
item in green reverse, done items dim/strikethrough, `[id]` badges feeding
`goto`/`enter`.

**Layout:** zellij KDL — Claude main pane (~72%), stack sidebar (~28%); a fixed
bottom-right corner variant is included.

**Setup (one-time):** create a venv and install `mcp[cli]` + `rich`; register the
server (`claude mcp add …` or a project `.mcp.json`); edit the absolute paths in the
KDL; launch with `zellij --layout claude-stack.kdl` from a project directory.

---

## 5. Current state

**Built (4 files):**

- `stack_server.py` — the MCP server (tree + cursor, atomic per-cwd persistence).
- `stack_view.py` — the live read-only sidebar viewer.
- `claude-stack.kdl` — the zellij layout (sidebar + corner variant).
- `README.md` — setup and usage.

**Verified** in a clean virtualenv:

- syntax compiles;
- all seven tools register under server name `mentalstack`;
- depth-first logic correct — e.g. `complete` on a child closes it and advances the
  cursor to the next open sibling;
- viewer renders the tree with cursor-path highlighting and a breadcrumb subtitle.

**Outstanding (your action):**

- one-time local setup (venv, server registration, KDL absolute paths);
- decide whether to commit `.mentalstack.json` per project or `.gitignore` it.

**Known limitations / deferred:**

- The viewer is **read-only**; all mutation goes through the Claude tools. (By design
  — keeps the command surface inside Claude per R3/D2.)
- The "in sight" view sits **beside** Claude Code, not inside it — unavoidable in a
  terminal (D4).
- Viewer refresh is a 0.4 s poll; swap to `watchfiles` for push-speed.
- Viewer is a plain `rich` panel; a `Textual` rebuild would add folding, scrolling,
  and keybindings without changing the JSON contract.

---

## 6. Possible next steps

1. `watchfiles`-based viewer for instant refresh.
2. `Textual` viewer with collapsible subtrees and keyboard navigation.
3. A `CLAUDE.md` snippet instructing Claude when to call the tools (draft in README).
4. Optional: bundle server + layout as a shareable package for the second team member.
