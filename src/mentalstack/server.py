# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Raphael Knaus
"""Mental-stack MCP server.

A per-project, depth-first "call stack" of work items, exposed to Claude Code as
MCP tools. State is persisted to .mentalstack.json in the process's working
directory (i.e. the project you launched `claude` in), so it survives across
many conversations and is automatically isolated per project.

Model: a tree of items with a single cursor.
  - the path from root to the cursor = your "open brackets"
  - `enter`  pushes a new sub-item and descends into it
  - `exit`   steps back up to the parent without finishing
  - `complete` closes the current item and moves to the next open sibling (else up)
  - `add`    queues a sibling at the current level (a not-yet-opened bracket)
  - `insert` adds a sibling before or after a given node (cursor stays)
  - `move`   reorders a node before or after a same-parent sibling
  - `goto`   jumps the cursor anywhere by id (descend into an existing item, or
             move sideways) — for the non-linear jumps
  - `refine` re-words the current item
  - `view`   returns the current path / children / what's next

Tools always return the rendered view so the state is also echoed into the chat.

Run:  uv run mentalstack-server        (stdio transport, the default)
"""
from __future__ import annotations

import functools
import json
import os
from pathlib import Path
from typing import Literal, Optional

from mcp.server.fastmcp import FastMCP

STATE_PATH = Path(os.environ.get("MENTALSTACK_FILE", ".mentalstack.json")).resolve()

mcp = FastMCP("mentalstack")


class StateUnreadableError(RuntimeError):
    """The state file exists but couldn't be read or parsed."""


# ----------------------------------------------------------------------------- state
def _new_state() -> dict:
    root = "0"
    return {
        "seq": 1,
        "root": root,
        "cursor": root,
        "nodes": {
            root: {"title": "(top level)", "status": "open",
                   "parent": None, "children": [], "notes": []},
        },
    }


def load() -> dict:
    """Read state from disk. Fresh state if the file is missing; raises
    StateUnreadableError if it exists but can't be parsed — so callers
    never silently overwrite a user's botched file."""
    try:
        with STATE_PATH.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return _new_state()
    except json.JSONDecodeError as e:
        raise StateUnreadableError(f"line {e.lineno}, col {e.colno}: {e.msg}") from e
    except OSError as e:
        raise StateUnreadableError(e.strerror or str(e)) from e


def _unreadable_msg(e: StateUnreadableError) -> str:
    return (f"⚠ state file unreadable; refusing to mutate.\n"
            f"{STATE_PATH}\n"
            f"{e}\n"
            f"Fix the file by hand, then retry.")


def _guard_unreadable(fn):
    """Surface StateUnreadableError as a chat message instead of an exception, so a corrupt file never causes a save() that wipes it."""
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except StateUnreadableError as e:
            return _unreadable_msg(e)
    return wrapper


def save(state: dict) -> None:
    # atomic write so the live viewer never reads a half-written file
    tmp = STATE_PATH.parent / (STATE_PATH.name + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, STATE_PATH)


def _id(state: dict) -> str:
    nid = str(state["seq"])
    state["seq"] += 1
    return nid


def _n(state, nid):
    return state["nodes"][nid]


def _path(state, nid) -> list[str]:
    """root -> nid (the open brackets)."""
    out, cur = [], nid
    while cur is not None:
        out.append(cur)
        cur = _n(state, cur)["parent"]
    return list(reversed(out))


def _next_open_sibling(state, nid) -> Optional[str]:
    parent = _n(state, nid)["parent"]
    if parent is None:
        return None
    sibs = _n(state, parent)["children"]
    for s in sibs[sibs.index(nid) + 1:]:
        if _n(state, s)["status"] == "open":
            return s
    return None


def render(state: dict) -> str:
    cur = state["cursor"]
    crumbs = " › ".join(_n(state, n)["title"] for n in _path(state, cur))
    lines = [f"📍 {crumbs}"]
    kids = _n(state, cur)["children"]
    if kids:
        lines.append("   children:")
        for k in kids:
            n = _n(state, k)
            lines.append(f"     [{k}] {'✓' if n['status'] == 'done' else '▸'} {n['title']}")
    nxt = _next_open_sibling(state, cur)
    if nxt:
        lines.append(f"   next after exit/complete: [{nxt}] {_n(state, nxt)['title']}")
    return "\n".join(lines)


# ----------------------------------------------------------------------------- tools
@mcp.tool()
@_guard_unreadable
def view() -> str:
    """Show the current stack: open brackets (path to cursor), current item, its children, and what's next."""
    return render(load())


@mcp.tool()
@_guard_unreadable
def enter(title: str) -> str:
    """Push a NEW sub-item under the current item and descend into it (open a bracket)."""
    state = load()
    nid = _id(state)
    parent = state["cursor"]
    state["nodes"][nid] = {"title": title, "status": "open",
                           "parent": parent, "children": [], "notes": []}
    _n(state, parent)["children"].append(nid)
    state["cursor"] = nid
    save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def exit() -> str:
    """Step back up to the parent item WITHOUT completing the current one."""
    state = load()
    parent = _n(state, state["cursor"])["parent"]
    if parent is not None:
        state["cursor"] = parent
        save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def complete(note: str = "") -> str:
    """Close the current item (mark done) and move to the next open sibling, else up to the parent."""
    state = load()
    cur = state["cursor"]
    _n(state, cur)["status"] = "done"
    if note:
        _n(state, cur).setdefault("notes", []).append(note)
    nxt = _next_open_sibling(state, cur)
    parent = _n(state, cur)["parent"]
    state["cursor"] = nxt or parent or cur
    save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def add(title: str) -> str:
    """Queue a sibling at the current level (a not-yet-opened bracket). The cursor does not move."""
    state = load()
    parent = _n(state, state["cursor"])["parent"] or state["root"]
    nid = _id(state)
    state["nodes"][nid] = {"title": title, "status": "open",
                           "parent": parent, "children": [], "notes": []}
    _n(state, parent)["children"].append(nid)
    save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def insert(title: str, anchor: str, where: Literal["before", "after"]) -> str:
    """Insert a NEW sibling before or after `anchor`. The cursor does not move."""
    state = load()
    if anchor not in state["nodes"]:
        return f"no item with id {anchor}\n" + render(state)
    parent = _n(state, anchor)["parent"]
    if parent is None:
        return "cannot insert sibling of root\n" + render(state)
    nid = _id(state)
    state["nodes"][nid] = {"title": title, "status": "open",
                           "parent": parent, "children": [], "notes": []}
    sibs = _n(state, parent)["children"]
    idx = sibs.index(anchor) + (1 if where == "after" else 0)
    sibs.insert(idx, nid)
    save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def move(id: str, anchor: str, where: Literal["before", "after"]) -> str:
    """Reorder `id` so it sits before or after `anchor`. Both must share a parent."""
    state = load()
    if id not in state["nodes"]:
        return f"no item with id {id}\n" + render(state)
    if anchor not in state["nodes"]:
        return f"no item with id {anchor}\n" + render(state)
    if id == anchor:
        return f"cannot move {id} relative to itself\n" + render(state)
    parent = _n(state, id)["parent"]
    if parent is None or _n(state, anchor)["parent"] != parent:
        return f"{id} and {anchor} are not siblings; same-parent moves only\n" + render(state)
    sibs = _n(state, parent)["children"]
    sibs.remove(id)
    idx = sibs.index(anchor) + (1 if where == "after" else 0)
    sibs.insert(idx, id)
    save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def goto(id: str) -> str:
    """Jump the cursor to any item by id — descend into an existing planned item or move sideways (non-linear)."""
    state = load()
    if id not in state["nodes"]:
        return f"no item with id {id}\n" + render(state)
    state["cursor"] = id
    save(state)
    return render(state)


@mcp.tool()
@_guard_unreadable
def refine(title: str) -> str:
    """Re-word the current item's title."""
    state = load()
    _n(state, state["cursor"])["title"] = title
    save(state)
    return render(state)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
