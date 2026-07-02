#!/usr/bin/env python3
"""state.py — durable on-disk state helper for the `handoff` skill.

Single source of truth per task is `.handoffs/<task_id>/state.json`.
`handoff.md` is a rendered view produced from it and is never hand-edited.

Subcommands (all read the task dir from argv[2] except `list`):
  init        Write initial state.json.
  set         Deep-key updates: `key=value` pairs (supports dotted paths and
              `attempts[-1].pid`). Values are parsed as JSON; fallback to str.
  get         Read a dotted path from state.json and print JSON.
  list        Walk `.handoffs/*/state.json` under cwd, emit JSON array.
  reconcile   Given a task dir, check pid + tail log for a terminal event and
              persist an updated state; also print the updated JSON.
  render      Render handoff.md from state.json.

All writes atomic (tmpfile + os.replace + fsync). Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ---------- atomic IO ---------------------------------------------------------

def _atomic_write(path: Path, data: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    # fsync the containing dir so the rename is durable
    dfd = os.open(str(path.parent), os.O_RDONLY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)


def _load(state_path: Path) -> dict[str, Any]:
    with open(state_path, "r", encoding="utf-8") as f:
        return json.load(f)


def _save(state_path: Path, state: dict[str, Any]) -> None:
    state["updated_at"] = now_iso()
    _atomic_write(state_path, json.dumps(state, indent=2, sort_keys=False) + "\n")


# ---------- dotted-path get/set ----------------------------------------------

_INDEX_RE = re.compile(r"^(?P<name>[^\[]+)?\[(?P<idx>-?\d+)\]$")


def _walk(obj: Any, path: str, *, create_missing: bool = False) -> tuple[Any, str | int]:
    """Walk to the parent container of `path`; return (parent, last_key)."""
    parts = path.split(".")
    cur = obj
    for part in parts[:-1]:
        m = _INDEX_RE.match(part)
        if m:
            name = m.group("name")
            idx = int(m.group("idx"))
            if name:
                cur = cur[name]
            cur = cur[idx]
        else:
            if create_missing and part not in cur:
                cur[part] = {}
            cur = cur[part]
    last = parts[-1]
    m = _INDEX_RE.match(last)
    if m:
        name = m.group("name")
        idx = int(m.group("idx"))
        if name:
            cur = cur[name]
        return cur, idx
    return cur, last


def _get(obj: Any, path: str) -> Any:
    parent, key = _walk(obj, path)
    return parent[key]


def _set(obj: Any, path: str, value: Any) -> None:
    parent, key = _walk(obj, path, create_missing=True)
    parent[key] = value


def _parse_value(raw: str) -> Any:
    try:
        return json.loads(raw)
    except Exception:
        return raw


# ---------- pid reconciliation -----------------------------------------------

def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def _pid_lstart(pid: int) -> str | None:
    try:
        out = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True, text=True, check=False,
        )
        if out.returncode != 0:
            return None
        s = out.stdout.strip()
        return s or None
    except Exception:
        return None


def _tail_lines(path: Path, n: int = 200) -> list[str]:
    if not path.exists():
        return []
    with open(path, "rb") as f:
        try:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            block = 4096
            data = b""
            while size > 0 and data.count(b"\n") <= n:
                step = min(block, size)
                size -= step
                f.seek(size)
                data = f.read(step) + data
            return data.decode("utf-8", errors="replace").splitlines()[-n:]
        except Exception:
            f.seek(0)
            return f.read().decode("utf-8", errors="replace").splitlines()[-n:]


def _extract_terminal(lines: list[str], backend: str) -> dict[str, Any] | None:
    """Find the backend's terminal event in the tail lines.

    cursor / claude stream-json: {"type":"result", is_error, usage, ...}
    codex --json: {"type":"turn.completed", ...} (best-effort).
    """
    for line in reversed(lines):
        line = line.strip()
        if not line or not (line.startswith("{") and line.endswith("}")):
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        t = obj.get("type")
        if backend in ("cursor-agent", "claude") and t == "result":
            return obj
        if backend == "codex" and t in ("turn.completed", "task.completed", "result"):
            return obj
    return None


def _reconcile(state: dict[str, Any], task_dir: Path) -> dict[str, Any]:
    if state.get("status") != "running":
        return state
    attempts = state.get("attempts") or []
    if not attempts:
        return state
    last = attempts[-1]
    pid = last.get("pid")
    log_name = last.get("log")
    if pid and _pid_alive(pid):
        # PID recycled check: if lstart differs from stored, treat as gone.
        stored_lstart = last.get("pid_start")
        cur_lstart = _pid_lstart(pid)
        if not (stored_lstart and cur_lstart and stored_lstart != cur_lstart):
            return state  # genuinely still running
        # else fall through: pid was recycled, treat as gone

    # Process is gone — inspect the log for a terminal event.
    log_path = task_dir / log_name if log_name else None
    terminal = None
    if log_path and log_path.exists():
        lines = _tail_lines(log_path, 400)
        terminal = _extract_terminal(lines, state.get("backend", ""))

    if terminal is None:
        state["status"] = "error"
        last["exit_code"] = None
        last["ended_at"] = now_iso()
        last["note"] = "process disappeared without terminal event"
    else:
        is_err = bool(terminal.get("is_error"))
        state["status"] = "error" if is_err else "done"
        last["ended_at"] = now_iso()
        last["exit_code"] = 1 if is_err else 0
        last["terminal"] = {
            k: terminal.get(k) for k in ("duration_ms", "is_error", "usage", "num_turns", "subtype")
            if k in terminal
        }
    return state


# ---------- render handoff.md ------------------------------------------------

COVER_TEMPLATE = """# Handoff — {task_id}

- **Status**: {status}
- **Task ID**: {task_id}
- **Backend**: {backend}
- **Session ID**: {session_id}
- **Workspace**: {workspace}
- **Model**: {model}
- **Started**: {created_at}
- **Updated**: {updated_at}
- **Takeover At**: {takeover_at}
- **Command**: `{command}`
- **Logs**:
{logs_list}

## Task

{task_block}

## Attempts

{attempts_block}

## Latest Summary

<!-- The dispatched agent MAY write a short summary here. -->

## What It Tried

<!-- Dispatched agent may append. -->

## Files Or Areas Touched

<!-- Dispatched agent may append paths. -->

## Errors Or Blockers

<!-- REQUIRED before stop: the dispatched agent MUST write concrete blockers verbatim
     here. The summary can lose context; this field must not. -->

## Recommended Next Step

<!-- Dispatched agent may propose the next step. -->

## Resume Prompt

Paste this into `handoff resume {task_id}` or a headless follow-up:

```
Continue the task tracked in .handoffs/{task_id}/handoff.md.
Read state.json for context. Prior attempts are in attempt-*.log.
```

## Headed Takeover Prompt

<!-- REQUIRED before stop: the dispatched agent MUST write a prompt here that a
     human (or Claude) can paste into an interactive session with the same backend
     and immediately have full context. The summary can lose context; this must not. -->

## Final Outcome

<!-- Fill in when status transitions to done / error / cancelled. -->
"""


def _render(state: dict[str, Any]) -> str:
    attempts = state.get("attempts") or []
    task = state.get("task") or ""
    task_block = "```\n" + task.strip() + "\n```" if task else "_(no task recorded)_"

    if attempts:
        rows = ["| # | started | ended | pid | exit | log |",
                "|---|---------|-------|-----|------|-----|"]
        for a in attempts:
            rows.append("| {n} | {s} | {e} | {p} | {x} | {l} |".format(
                n=a.get("n"),
                s=a.get("started_at", "-"),
                e=a.get("ended_at", "-") or "-",
                p=a.get("pid", "-") or "-",
                x=a.get("exit_code", "-") if a.get("exit_code") is not None else "-",
                l=a.get("log", "-"),
            ))
        attempts_block = "\n".join(rows)
    else:
        attempts_block = "_(no attempts)_"

    logs = [a.get("log") for a in attempts if a.get("log")]
    logs_list = "\n".join(f"  - `{l}`" for l in logs) if logs else "  - _(none)_"

    return COVER_TEMPLATE.format(
        task_id=state.get("task_id", "?"),
        status=state.get("status", "?"),
        backend=state.get("backend", "?"),
        session_id=state.get("session_id") or "(none)",
        workspace=state.get("workspace") or "?",
        model=state.get("model") or "(default)",
        created_at=state.get("created_at", "?"),
        updated_at=state.get("updated_at", "?"),
        takeover_at=state.get("takeover_at") or "(none)",
        command=state.get("command", "?"),
        logs_list=logs_list,
        task_block=task_block,
        attempts_block=attempts_block,
    )


# ---------- subcommands ------------------------------------------------------

def cmd_init(args: argparse.Namespace) -> int:
    task_dir = Path(args.task_dir).resolve()
    task_dir.mkdir(parents=True, exist_ok=True)
    state_path = task_dir / "state.json"
    ts = now_iso()
    state: dict[str, Any] = {
        "task_id": args.task_id,
        "backend": args.backend,
        "session_id": args.session_id or None,
        "task": args.task,
        "workspace": args.workspace,
        "model": args.model or None,
        "status": "running",
        "attempts": [{
            "n": 1,
            "started_at": ts,
            "ended_at": None,
            "pid": None,
            "pid_start": None,
            "exit_code": None,
            "log": "attempt-1.log",
        }],
        "command": args.command or "",
        "created_at": ts,
        "updated_at": ts,
        "takeover_at": None,
    }
    _save(state_path, state)
    (task_dir / "handoff.md").write_text(_render(state), encoding="utf-8")
    print(json.dumps({"task_id": args.task_id, "state": str(state_path)}))
    return 0


def cmd_set(args: argparse.Namespace) -> int:
    task_dir = Path(args.task_dir).resolve()
    state_path = task_dir / "state.json"
    state = _load(state_path)
    for kv in args.pairs:
        if "=" not in kv:
            print(f"bad pair: {kv}", file=sys.stderr)
            return 2
        k, v = kv.split("=", 1)
        _set(state, k, _parse_value(v))
    _save(state_path, state)
    (task_dir / "handoff.md").write_text(_render(state), encoding="utf-8")
    return 0


def cmd_get(args: argparse.Namespace) -> int:
    state = _load(Path(args.task_dir) / "state.json")
    val = _get(state, args.path)
    if isinstance(val, str):
        print(val)
    else:
        print(json.dumps(val))
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    root = Path(args.root or ".").resolve() / ".handoffs"
    out: list[dict[str, Any]] = []
    if root.exists():
        for entry in sorted(root.iterdir()):
            sp = entry / "state.json"
            if not sp.exists():
                continue
            try:
                state = _load(sp)
            except Exception:
                continue
            state = _reconcile(state, entry)
            _save(sp, state)
            (entry / "handoff.md").write_text(_render(state), encoding="utf-8")
            out.append(state)
    out.sort(key=lambda s: s.get("updated_at", ""), reverse=True)
    if args.status:
        out = [s for s in out if s.get("status") == args.status]
    print(json.dumps(out, indent=2))
    return 0


def cmd_reconcile(args: argparse.Namespace) -> int:
    task_dir = Path(args.task_dir).resolve()
    state_path = task_dir / "state.json"
    state = _load(state_path)
    state = _reconcile(state, task_dir)
    _save(state_path, state)
    (task_dir / "handoff.md").write_text(_render(state), encoding="utf-8")
    print(json.dumps(state, indent=2))
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    task_dir = Path(args.task_dir).resolve()
    state = _load(task_dir / "state.json")
    (task_dir / "handoff.md").write_text(_render(state), encoding="utf-8")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="state.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("init")
    pi.add_argument("--task-dir", required=True)
    pi.add_argument("--task-id", required=True)
    pi.add_argument("--backend", required=True)
    pi.add_argument("--session-id", default="")
    pi.add_argument("--task", required=True)
    pi.add_argument("--workspace", required=True)
    pi.add_argument("--model", default="")
    pi.add_argument("--command", default="")
    pi.set_defaults(func=cmd_init)

    ps = sub.add_parser("set")
    ps.add_argument("--task-dir", required=True)
    ps.add_argument("pairs", nargs="+")
    ps.set_defaults(func=cmd_set)

    pg = sub.add_parser("get")
    pg.add_argument("--task-dir", required=True)
    pg.add_argument("path")
    pg.set_defaults(func=cmd_get)

    pl = sub.add_parser("list")
    pl.add_argument("--root", default=".")
    pl.add_argument("--status", default="")
    pl.set_defaults(func=cmd_list)

    pr = sub.add_parser("reconcile")
    pr.add_argument("--task-dir", required=True)
    pr.set_defaults(func=cmd_reconcile)

    pd = sub.add_parser("render")
    pd.add_argument("--task-dir", required=True)
    pd.set_defaults(func=cmd_render)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
