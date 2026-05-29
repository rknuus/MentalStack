# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Raphael Knaus
"""Live corner view of the mental stack.

Watches .mentalstack.json (written by mentalstack-server) and re-renders on
every change. Read-only — all mutation happens through the MCP tools in
Claude. Meant to run in a small zellij pane beside Claude Code.

  open brackets (path to cursor) -> yellow
  current item (cursor)          -> bold reverse green
  done items                     -> dim strikethrough
  [id] badges                    -> use with `goto`/`enter` in Claude

Run:  uv run mentalstack-view
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path

from rich.live import Live
from rich.panel import Panel
from rich.text import Text
from rich.tree import Tree

STATE_PATH = Path(os.environ.get("MENTALSTACK_FILE", ".mentalstack.json")).resolve()
POLL_SECONDS = 0.4


def load():
    """Read the state file. Return ("ok", state), ("empty", None), or ("error", msg)."""
    try:
        with STATE_PATH.open(encoding="utf-8") as f:
            return ("ok", json.load(f))
    except FileNotFoundError:
        return ("empty", None)
    except json.JSONDecodeError as e:
        return ("error", f"line {e.lineno}, col {e.colno}: {e.msg}")
    except OSError as e:
        return ("error", e.strerror or str(e))


def path_to(state, nid) -> list[str]:
    out, cur = [], nid
    while cur is not None:
        out.append(cur)
        cur = state["nodes"][cur]["parent"]
    return list(reversed(out))


def _add_children(state, parent_id, branch, on_path: set, cursor: str):
    for cid in state["nodes"][parent_id]["children"]:
        n = state["nodes"][cid]
        done = n["status"] == "done"
        prefix = "✓ " if done else "▸ "
        label = Text()
        if cid == cursor:
            label.append(prefix + n["title"], style="bold reverse green")
        elif cid in on_path:
            label.append(prefix + n["title"], style="yellow")
        elif done:
            label.append(prefix + n["title"], style="dim strike")
        else:
            label.append(prefix + n["title"])
        label.append(f"  [{cid}]", style="dim")
        _add_children(state, cid, branch.add(label), on_path, cursor)


def build(result):
    kind, payload = result
    if kind == "empty":
        return Panel("no stack yet —\nuse the tools in Claude",
                     title="🧠 mental stack")
    if kind == "error":
        body = Text()
        body.append("⚠ can't read state file\n", style="bold red")
        body.append(STATE_PATH.name + "\n", style="dim")
        body.append(payload, style="red")
        return Panel(body, title="🧠 mental stack", border_style="red")
    state = payload
    cursor = state["cursor"]
    on_path = set(path_to(state, cursor))
    root_id = state["root"]
    tree = Tree(Text(state["nodes"][root_id]["title"], style="bold"))
    _add_children(state, root_id, tree, on_path, cursor)
    crumbs = " › ".join(state["nodes"][n]["title"] for n in path_to(state, cursor))
    return Panel(tree, title="🧠 mental stack",
                 subtitle=crumbs, subtitle_align="left")


def _run() -> None:
    last = object()
    with Live(build(load()), refresh_per_second=4, screen=True) as live:
        while True:
            try:
                stamp = STATE_PATH.stat().st_mtime
            except FileNotFoundError:
                stamp = None
            if stamp != last:
                last = stamp
                live.update(build(load()))
            time.sleep(POLL_SECONDS)


def main() -> None:
    try:
        _run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
