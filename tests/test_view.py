"""Unit tests for ``mentalstack.view``.

Covers ``path_to``, ``_add_children`` styling, ``build()`` for every result
kind, and ``load()`` for every outcome.

``_run`` is *not* tested end-to-end — it's an infinite ``Live`` poll loop,
not designed for headless testing. Its constituent pieces (``build`` and
``load``) carry the testable behaviour.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

from rich.console import Console
from rich.text import Text
from rich.tree import Tree


def _find_label(tree: Tree, substring: str) -> Text | None:
    """Recursively find a label whose plain text contains ``substring``."""
    if isinstance(tree.label, Text) and substring in tree.label.plain:
        return tree.label
    for child in tree.children:
        found = _find_label(child, substring)
        if found is not None:
            return found
    return None


def _render(renderable: Any) -> str:
    """Render a Rich renderable to plain text (no ANSI)."""
    console = Console(record=True, force_terminal=False)
    console.print(renderable)
    return console.export_text()


# --------------------------------------------------------------------------- path_to


class TestPathTo:
    def test_root_path_is_just_root(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        assert view.path_to(populated_state(), "0") == ["0"]

    def test_walks_through_parents(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # 2 → 1 → 0, reversed
        assert view.path_to(populated_state(), "2") == ["0", "1", "2"]


# --------------------------------------------------------------------------- _add_children


def _build_branch(view: ModuleType, state: dict[str, Any]) -> Tree:
    """Run ``_add_children`` once against a state and return the populated Tree."""
    tree = Tree(Text("root"))
    on_path = set(view.path_to(state, state["cursor"]))
    view._add_children(state, "0", tree, on_path, state["cursor"])
    return tree


class TestAddChildren:
    def test_cursor_node_gets_bold_reverse_green(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # cursor is on "parent" (id "1") in populated_state
        tree = _build_branch(view, populated_state())
        label = _find_label(tree, "parent")
        assert label is not None
        styles = {str(s.style) for s in label.spans}
        assert "bold reverse green" in styles

    def test_on_path_node_gets_yellow(self, view: ModuleType) -> None:
        # Hand-built tree with a deeper cursor so node "1" is on the path
        # but not the cursor itself.
        state: dict[str, Any] = {
            "seq": 4,
            "root": "0",
            "cursor": "3",
            "nodes": {
                "0": {
                    "title": "root",
                    "status": "open",
                    "parent": None,
                    "children": ["1"],
                    "notes": [],
                },
                "1": {
                    "title": "mid",
                    "status": "open",
                    "parent": "0",
                    "children": ["2", "3"],
                    "notes": [],
                },
                "2": {
                    "title": "uncle",
                    "status": "open",
                    "parent": "1",
                    "children": [],
                    "notes": [],
                },
                "3": {
                    "title": "cursor-here",
                    "status": "open",
                    "parent": "1",
                    "children": [],
                    "notes": [],
                },
            },
        }
        tree = _build_branch(view, state)
        label = _find_label(tree, "mid")
        assert label is not None
        styles = {str(s.style) for s in label.spans}
        assert "yellow" in styles

    def test_done_node_gets_dim_strike(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # node "4" ("c") is done in populated_state
        tree = _build_branch(view, populated_state())
        label = _find_label(tree, "c")
        assert label is not None
        styles = {str(s.style) for s in label.spans}
        assert "dim strike" in styles

    def test_default_node_has_no_color_style(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # Node 2 ("a"): not cursor, not on_path (path is {0, 1}), not done.
        # Look up by [2] badge — "a" alone is also a substring of "parent".
        tree = _build_branch(view, populated_state())
        label = _find_label(tree, "[2]")
        assert label is not None
        title_style = str(label.spans[0].style)
        assert "bold reverse green" not in title_style
        assert "yellow" not in title_style
        assert "dim strike" not in title_style

    def test_id_badge_present_on_every_node(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        tree = _build_branch(view, populated_state())
        for cid in ["1", "2", "3", "4"]:
            assert _find_label(tree, f"[{cid}]") is not None, f"missing [{cid}] badge"

    def test_id_badge_has_dim_style(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        tree = _build_branch(view, populated_state())
        label = _find_label(tree, "[2]")
        assert label is not None
        # the badge is the last appended span
        badge_span = next(s for s in label.spans if "[2]" in label.plain[s.start : s.end])
        assert "dim" in str(badge_span.style)


# --------------------------------------------------------------------------- build


class TestBuild:
    def test_empty_renders_no_stack_yet(self, view: ModuleType) -> None:
        out = _render(view.build(("empty", None)))
        assert "no stack yet" in out
        assert "mental stack" in out

    def test_error_renders_filename_and_message(self, view: ModuleType) -> None:
        out = _render(view.build(("error", "line 1, col 5: Expecting value")))
        assert "can't read state file" in out
        assert view.STATE_PATH.name in out
        assert "Expecting value" in out

    def test_error_panel_uses_red_border_style(self, view: ModuleType) -> None:
        panel = view.build(("error", "boom"))
        assert "red" in str(panel.border_style)

    def test_ok_renders_tree_content(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        out = _render(view.build(("ok", populated_state())))
        assert "(top level)" in out
        assert "parent" in out
        for title in ("a", "b", "c"):
            assert title in out

    def test_ok_panel_subtitle_is_crumbs(
        self, view: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        s = populated_state()
        panel = view.build(("ok", s))
        expected = " › ".join(s["nodes"][n]["title"] for n in view.path_to(s, s["cursor"]))
        assert str(panel.subtitle) == expected


# --------------------------------------------------------------------------- load


class TestLoad:
    def test_missing_file_returns_empty(self, view: ModuleType, state_file: Path) -> None:
        assert view.load() == ("empty", None)

    def test_clean_file_returns_ok_with_state(
        self,
        view: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        s = populated_state()
        state_file.write_text(json.dumps(s), encoding="utf-8")
        kind, payload = view.load()
        assert kind == "ok"
        assert payload == s

    def test_corrupt_file_returns_error_with_line_info(
        self, view: ModuleType, state_file: Path
    ) -> None:
        state_file.write_text("{not valid", encoding="utf-8")
        kind, payload = view.load()
        assert kind == "error"
        assert isinstance(payload, str)
        assert "line 1" in payload

    def test_directory_at_state_path_returns_error(
        self, view: ModuleType, state_file: Path
    ) -> None:
        state_file.mkdir()
        kind, payload = view.load()
        assert kind == "error"
        assert isinstance(payload, str)
        assert payload  # non-empty message
