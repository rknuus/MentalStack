"""Unit tests for ``mentalstack.server``.

Covers pure helpers, load/save, every MCP tool, the @_guard_unreadable
decorator, and schema invariants. Each ``Test<Group>`` class focuses on one
piece of the public surface; test names describe behaviour, not mechanics.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

NODE_KEYS = {"title", "status", "parent", "children", "notes"}


# --------------------------------------------------------------------------- pure helpers


class TestNewState:
    def test_seq_starts_at_one(self, server: ModuleType) -> None:
        assert server._new_state()["seq"] == 1

    def test_root_and_cursor_at_zero(self, server: ModuleType) -> None:
        s = server._new_state()
        assert s["root"] == "0"
        assert s["cursor"] == "0"

    def test_root_node_open_with_no_parent(self, server: ModuleType) -> None:
        node = server._new_state()["nodes"]["0"]
        assert node["status"] == "open"
        assert node["parent"] is None
        assert node["children"] == []
        assert node["notes"] == []


class TestId:
    def test_returns_current_seq_as_str(
        self, server: ModuleType, fresh_state: Callable[[], dict[str, Any]]
    ) -> None:
        s = fresh_state()
        assert server._id(s) == "1"

    def test_increments_seq(
        self, server: ModuleType, fresh_state: Callable[[], dict[str, Any]]
    ) -> None:
        s = fresh_state()
        server._id(s)
        assert s["seq"] == 2

    def test_sequential_calls_yield_distinct_ids(
        self, server: ModuleType, fresh_state: Callable[[], dict[str, Any]]
    ) -> None:
        s = fresh_state()
        assert [server._id(s) for _ in range(3)] == ["1", "2", "3"]


class TestPath:
    def test_root_path_is_just_root(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        assert server._path(populated_state(), "0") == ["0"]

    def test_descendant_walks_back_through_parents(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # node 2 → 1 → 0, reversed
        assert server._path(populated_state(), "2") == ["0", "1", "2"]


class TestNextOpenSibling:
    def test_returns_none_for_root(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        assert server._next_open_sibling(populated_state(), "0") is None

    def test_returns_next_open_sibling(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # siblings of 2 in order: [3 open, 4 done]
        assert server._next_open_sibling(populated_state(), "2") == "3"

    def test_skips_done_siblings(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        # siblings after 3 in order: [4 done]
        assert server._next_open_sibling(populated_state(), "3") is None

    def test_returns_none_when_no_siblings_after(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        assert server._next_open_sibling(populated_state(), "4") is None


class TestRender:
    def test_includes_path_crumbs(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        out = server.render(populated_state())
        assert "(top level)" in out
        assert "parent" in out

    def test_lists_children_with_ids(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        out = server.render(populated_state())
        for cid, title in [("2", "a"), ("3", "b"), ("4", "c")]:
            assert f"[{cid}]" in out
            assert title in out

    def test_done_children_get_checkmark(
        self, server: ModuleType, populated_state: Callable[[], dict[str, Any]]
    ) -> None:
        out = server.render(populated_state())
        assert "✓" in out  # node 4 is done

    def test_omits_children_line_when_empty(
        self, server: ModuleType, fresh_state: Callable[[], dict[str, Any]]
    ) -> None:
        assert "children:" not in server.render(fresh_state())


# --------------------------------------------------------------------------- load / save


class TestLoad:
    def test_missing_file_returns_fresh_state(self, server: ModuleType, state_file: Path) -> None:
        assert not state_file.exists()
        s = server.load()
        assert s["seq"] == 1
        assert s["root"] == "0"

    def test_clean_file_round_trips(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        s = populated_state()
        state_file.write_text(json.dumps(s), encoding="utf-8")
        assert server.load() == s

    def test_corrupt_file_raises_with_line_info(self, server: ModuleType, state_file: Path) -> None:
        state_file.write_text("{not valid json", encoding="utf-8")
        with pytest.raises(server.StateUnreadableError) as exc:
            server.load()
        assert "line 1" in str(exc.value)

    def test_directory_at_state_path_raises(self, server: ModuleType, state_file: Path) -> None:
        state_file.mkdir()
        with pytest.raises(server.StateUnreadableError):
            server.load()


class TestSave:
    def test_writes_round_trippable_json(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        s = populated_state()
        server.save(s)
        assert state_file.exists()
        assert json.loads(state_file.read_text(encoding="utf-8")) == s

    def test_atomic_via_tmp_then_replace(
        self,
        server: ModuleType,
        state_file: Path,
        fresh_state: Callable[[], dict[str, Any]],
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        recorded: list[tuple[Path, Path]] = []
        real_replace = server.os.replace

        def fake_replace(src: Any, dst: Any) -> Any:
            recorded.append((Path(src), Path(dst)))
            return real_replace(src, dst)

        monkeypatch.setattr(server.os, "replace", fake_replace)
        server.save(fresh_state())
        assert len(recorded) == 1
        src, dst = recorded[0]
        assert src.name.endswith(".tmp")
        assert dst == state_file


# --------------------------------------------------------------------------- tools


class TestView:
    def test_returns_rendered_string(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        out = server.view()
        assert "parent" in out
        assert "[2]" in out


class TestEnter:
    def test_pushes_child_under_cursor(self, server: ModuleType, state_file: Path) -> None:
        server.enter("hello")
        s = server.load()
        assert s["nodes"]["1"]["title"] == "hello"
        assert s["nodes"]["1"]["parent"] == "0"
        assert "1" in s["nodes"]["0"]["children"]

    def test_moves_cursor_to_new_node(self, server: ModuleType, state_file: Path) -> None:
        server.enter("foo")
        assert server.load()["cursor"] == "1"


class TestExit:
    def test_moves_cursor_to_parent(self, server: ModuleType, state_file: Path) -> None:
        server.enter("a")  # cursor → "1"
        server.exit()
        assert server.load()["cursor"] == "0"

    def test_noop_at_root(self, server: ModuleType, state_file: Path) -> None:
        server.exit()
        # state file may or may not exist depending on whether the no-op saved;
        # what matters is the cursor stays at root once we observe state
        s = server.load()
        assert s["cursor"] == "0"


class TestComplete:
    def test_marks_current_done(self, server: ModuleType, state_file: Path) -> None:
        server.enter("task")
        server.complete()
        assert server.load()["nodes"]["1"]["status"] == "done"

    def test_jumps_to_next_open_sibling(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        s = populated_state()
        s["cursor"] = "2"  # complete 'a' → next open sibling is '3' (b)
        server.save(s)
        server.complete()
        assert server.load()["cursor"] == "3"

    def test_jumps_to_parent_when_no_open_sibling(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        s = populated_state()
        s["cursor"] = "3"  # next sibling is 4 (done), no open after → up to 1
        server.save(s)
        server.complete()
        assert server.load()["cursor"] == "1"

    def test_cursor_stays_when_complete_at_root(self, server: ModuleType, state_file: Path) -> None:
        server.complete()
        assert server.load()["cursor"] == "0"

    def test_appends_note_when_provided(self, server: ModuleType, state_file: Path) -> None:
        server.enter("task")
        server.complete(note="done well")
        assert "done well" in server.load()["nodes"]["1"]["notes"]

    def test_no_note_when_empty(self, server: ModuleType, state_file: Path) -> None:
        server.enter("task")
        server.complete()
        assert server.load()["nodes"]["1"]["notes"] == []


class TestAdd:
    def test_queues_at_cursor_parent_level(self, server: ModuleType, state_file: Path) -> None:
        server.enter("first")  # cursor "1", parent "0"
        server.add("peer")  # peer joins "0"'s children, not "1"'s
        s = server.load()
        assert s["nodes"]["2"]["parent"] == "0"
        assert "2" in s["nodes"]["0"]["children"]

    def test_cursor_does_not_move(self, server: ModuleType, state_file: Path) -> None:
        server.enter("first")
        before = server.load()["cursor"]
        server.add("peer")
        assert server.load()["cursor"] == before


class TestInsert:
    def test_before_anchor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.insert("middle", "3", "before")
        assert server.load()["nodes"]["1"]["children"] == ["2", "5", "3", "4"]

    def test_after_anchor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.insert("end", "4", "after")
        assert server.load()["nodes"]["1"]["children"] == ["2", "3", "4", "5"]

    def test_cursor_does_not_move(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        before = server.load()["cursor"]
        server.insert("x", "2", "before")
        assert server.load()["cursor"] == before

    def test_refuses_unknown_anchor(self, server: ModuleType, state_file: Path) -> None:
        out = server.insert("x", "99", "before")
        assert "no item with id 99" in out

    def test_refuses_root_sibling(self, server: ModuleType, state_file: Path) -> None:
        out = server.insert("x", "0", "after")
        assert "cannot insert sibling of root" in out


class TestMove:
    def test_before_anchor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.move("4", "2", "before")
        assert server.load()["nodes"]["1"]["children"] == ["4", "2", "3"]

    def test_after_anchor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.move("2", "4", "after")
        assert server.load()["nodes"]["1"]["children"] == ["3", "4", "2"]

    def test_refuses_unknown_id(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        out = server.move("99", "2", "before")
        assert "no item with id 99" in out

    def test_refuses_unknown_anchor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        out = server.move("2", "99", "before")
        assert "no item with id 99" in out

    def test_refuses_self_move(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        out = server.move("2", "2", "before")
        assert "relative to itself" in out

    def test_refuses_cross_parent(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        # move 2 (child of 1) relative to 0 (root, no parent) → not siblings
        out = server.move("2", "0", "before")
        assert "not siblings" in out

    def test_refuses_moving_root(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        out = server.move("0", "1", "before")
        assert "not siblings" in out


class TestGoto:
    def test_jumps_cursor_to_existing(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.goto("3")
        assert server.load()["cursor"] == "3"

    def test_refuses_unknown_id_without_moving_cursor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        before = server.load()["cursor"]
        out = server.goto("99")
        assert "no item with id 99" in out
        assert server.load()["cursor"] == before


class TestRefine:
    def test_renames_cursor(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.refine("renamed!")
        assert server.load()["nodes"]["1"]["title"] == "renamed!"


# --------------------------------------------------------------------------- guard

TOOL_CALLS: list[tuple[str, tuple[Any, ...]]] = [
    ("view", ()),
    ("enter", ("x",)),
    ("exit", ()),
    ("complete", ()),
    ("add", ("x",)),
    ("insert", ("x", "0", "after")),
    ("move", ("0", "1", "before")),
    ("goto", ("0",)),
    ("refine", ("x",)),
]


class TestGuardUnreadable:
    def test_returns_warning_on_corrupt_file(self, server: ModuleType, state_file: Path) -> None:
        state_file.write_text("{garbage", encoding="utf-8")
        out = server.enter("hello")
        assert out.startswith("⚠")
        assert "refusing to mutate" in out

    def test_corrupt_file_byte_identical_after_refused_call(
        self, server: ModuleType, state_file: Path
    ) -> None:
        corrupt = "{garbage}"
        state_file.write_text(corrupt, encoding="utf-8")
        before = state_file.read_bytes()
        server.enter("hello")
        assert state_file.read_bytes() == before

    @pytest.mark.parametrize(("name", "args"), TOOL_CALLS, ids=[n for n, _ in TOOL_CALLS])
    def test_every_tool_refuses_on_corrupt_file(
        self,
        server: ModuleType,
        state_file: Path,
        name: str,
        args: tuple[Any, ...],
    ) -> None:
        state_file.write_text("{garbage", encoding="utf-8")
        before = state_file.read_bytes()
        out = getattr(server, name)(*args)
        assert out.startswith("⚠"), f"{name} did not refuse on corrupt file: {out!r}"
        assert state_file.read_bytes() == before, f"{name} mutated the corrupt file"


# --------------------------------------------------------------------------- schema invariants


class TestSchemaInvariants:
    def test_new_state_root_has_expected_keys(
        self, server: ModuleType, fresh_state: Callable[[], dict[str, Any]]
    ) -> None:
        assert set(fresh_state()["nodes"]["0"]) == NODE_KEYS

    def test_enter_creates_node_with_expected_keys(
        self, server: ModuleType, state_file: Path
    ) -> None:
        server.enter("foo")
        assert set(server.load()["nodes"]["1"]) == NODE_KEYS

    def test_add_creates_node_with_expected_keys(
        self, server: ModuleType, state_file: Path
    ) -> None:
        server.add("foo")
        new_id = max(server.load()["nodes"].keys(), key=int)
        assert set(server.load()["nodes"][new_id]) == NODE_KEYS

    def test_insert_creates_node_with_expected_keys(
        self,
        server: ModuleType,
        state_file: Path,
        populated_state: Callable[[], dict[str, Any]],
    ) -> None:
        server.save(populated_state())
        server.insert("inserted", "2", "before")
        new_id = max(server.load()["nodes"].keys(), key=int)
        assert set(server.load()["nodes"][new_id]) == NODE_KEYS
