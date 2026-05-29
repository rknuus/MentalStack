# Mental-stack for Claude Code (zellij + corner TUI + MCP server)

A per-project depth-first "call stack" of work items. You mutate it from inside
Claude Code via MCP tools; a live TUI pinned in a zellij sidebar always shows
where you are and what's next. State persists per project and survives across
conversations.

```
┌──────────────────────────────┬────────────────────┐
│                              │ 🧠 mental stack    │
│   Claude Code (claude)       │ (top level)        │
│                              │ ▸ ship release [1] │
│   ...calls enter/exit/...    │  ✓ changelog  [2]  │
│                              │  ▸ cut RC     [3]  │ ← cursor
│                              │    ▸ sign     [5]  │
│                              │                    │
└──────────────────────────────┴────────────────────┘
```

Two processes share one JSON file in the project directory. The MCP server
(launched by Claude) writes it atomically; the viewer watches it. No daemon, no
socket. Because the file lives in the project's cwd, each project is isolated
automatically.

## 1. Install

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then
from a clone of this repo:

```bash
uv sync
```

That's it — `uv` creates a `.venv/`, installs the pinned dependencies from
`uv.lock`, and registers the `mentalstack-server` and `mentalstack-view`
console entry points.

## 2. Register the MCP server with Claude Code

Either globally:

```bash
claude mcp add mentalstack -- uv run --project /ABS/PATH/to/MentalStack mentalstack-server
```

…or per project, by dropping a `.mcp.json` in the project root:

```json
{
  "mcpServers": {
    "mentalstack": {
      "command": "uv",
      "args": ["run", "--project", "/ABS/PATH/to/MentalStack", "mentalstack-server"]
    }
  }
}
```

`uv run --project <path>` always resolves the entry point against this repo's
pinned environment, no matter what cwd Claude launches it from.

## 3. Wire up the layout

`claude-stack.kdl` lives in this repo. Open it once and replace the single
`/ABS/PATH/to/MentalStack` placeholder with the absolute path to your local
clone — that one edit is reused across every project.

Then, `cd` into whichever project you want to work in and launch zellij
against the file in your clone:

```bash
zellij --layout /ABS/PATH/to/MentalStack/claude-stack.kdl
```

You launch from the project's directory (not from the MentalStack clone) so
both panes inherit that project's cwd and share its `.mentalstack.json`.

If you'd rather not type the full path each time, copy the edited file to
`~/.config/zellij/layouts/claude-stack.kdl` and launch with
`zellij --layout claude-stack` instead.

## 4. Use it

In the Claude pane, drive the stack in natural language — Claude calls the
tools, the sidebar updates within ~0.4 s:

| You / Claude            | Tool        | Effect                                        |
|-------------------------|-------------|-----------------------------------------------|
| dive into a sub-task    | `enter`     | push a child, descend (open a bracket)        |
| step back up            | `exit`      | move to parent, nothing closed                |
| done with this          | `complete`  | close it, jump to next open sibling / up      |
| note a peer task        | `add`       | queue a sibling, cursor stays                 |
| insert at a position    | `insert`    | new sibling before/after a given node, cursor stays |
| reorder siblings        | `move`      | move a node before/after a same-parent sibling |
| jump anywhere           | `goto <id>` | descend into an existing item / move sideways |
| re-word current         | `refine`    | rename the current item                       |
| where am I?             | `view`      | print path + children + what's next           |

A good `CLAUDE.md` line for the project:

> Track multi-step work with the `mentalstack` tools: `enter` when diving into a
> sub-task, `complete` when a step is done, `add` to queue peer steps. Call
> `view` if you lose the thread.

## Notes / next steps

- **Cursor styling:** open-bracket path = yellow, current = green reverse, done =
  dim strikethrough, `[id]` badges feed `goto`/`enter`.
- **Instant updates:** swap the 0.4 s poll in `mentalstack/view.py` for
  `watchfiles` if you want push-speed refresh.
- **Richer viewer:** the panel is plain `rich`; promote to a Textual app if you
  want folding, scrolling, or keybindings.
- **History rewrite-safe:** state is just JSON; commit `.mentalstack.json` per
  project or add it to `.gitignore`, your call.
- **Planned dev tooling** (ruff, pytest, mypy) is captured in [`TODO.md`](TODO.md)
  for a follow-up initiative.

## License

MentalStack is released under the [GNU General Public License v3.0 or later](LICENSE).

Copyright (C) 2026 Raphael Knaus.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.
