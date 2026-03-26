#!/usr/bin/env python3
"""
Analyze Claude Code session logs for token usage.

Reads JSONL session logs and reports:
- Total input, output, cache-creation, cache-read tokens
- Per-turn breakdown
- Identifies high-cost turns

Usage:
    python3 scripts/session-token-analysis.py <session-id>
    python3 scripts/session-token-analysis.py <path-to-jsonl>
    python3 scripts/session-token-analysis.py --list   # list available sessions

Session logs are in ~/.claude/projects/<project-key>/<session-id>.jsonl
"""

import json
import sys
import os
from pathlib import Path


def find_project_dir():
    """Find the project session directory based on CWD."""
    cwd = os.getcwd()
    # Claude Code uses the CWD path with / replaced by - as the project key
    key = cwd.replace("/", "-")
    if not key.startswith("-"):
        key = "-" + key
    project_dir = Path.home() / ".claude" / "projects" / key
    if project_dir.exists():
        return project_dir
    # Try alternate: some versions use different separator logic
    # Search for a directory containing our basename
    projects_dir = Path.home() / ".claude" / "projects"
    if projects_dir.exists():
        basename = Path(cwd).name
        for d in projects_dir.iterdir():
            if d.is_dir() and basename in d.name:
                return d
    return None


def list_sessions(project_dir):
    """List available session JSONL files."""
    if not project_dir:
        print("No project directory found for current working directory.")
        return
    jsonl_files = sorted(project_dir.glob("*.jsonl"))
    if not jsonl_files:
        print("No session logs found.")
        return
    print(f"Available sessions in {project_dir}:\n")
    for f in jsonl_files:
        session_id = f.stem
        size_kb = f.stat().st_size / 1024
        print(f"  {session_id}  ({size_kb:.0f} KB)")


def resolve_jsonl_path(arg):
    """Resolve a session ID or path to a JSONL file."""
    path = Path(arg)
    if path.exists() and path.suffix == ".jsonl":
        return path
    # Try as session ID in project dir
    project_dir = find_project_dir()
    if project_dir:
        candidate = project_dir / f"{arg}.jsonl"
        if candidate.exists():
            return candidate
    print(f"Could not find session log: {arg}")
    sys.exit(1)


def analyze_session(jsonl_path):
    """Parse JSONL and extract token usage."""
    totals = {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
    }
    turns = []
    turn_num = 0

    with open(jsonl_path) as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            if entry.get("type") != "assistant":
                continue

            msg = entry.get("message", {})
            usage = msg.get("usage", {})
            if not usage:
                continue

            turn_num += 1
            inp = usage.get("input_tokens", 0)
            out = usage.get("output_tokens", 0)
            cache_create = usage.get("cache_creation_input_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            model = msg.get("model", "unknown")

            # Check if this is a subagent turn
            is_sidechain = entry.get("isSidechain", False)

            totals["input_tokens"] += inp
            totals["output_tokens"] += out
            totals["cache_creation_input_tokens"] += cache_create
            totals["cache_read_input_tokens"] += cache_read

            turns.append({
                "turn": turn_num,
                "input": inp,
                "output": out,
                "cache_create": cache_create,
                "cache_read": cache_read,
                "model": model,
                "sidechain": is_sidechain,
                "total_context": inp + cache_create + cache_read,
            })

    return totals, turns


def print_report(jsonl_path, totals, turns):
    """Print analysis report."""
    session_id = jsonl_path.stem

    print(f"\n=== Session Token Analysis: {session_id} ===\n")

    print("Totals:")
    print(f"  Input tokens:          {totals['input_tokens']:>12,}")
    print(f"  Output tokens:         {totals['output_tokens']:>12,}")
    print(f"  Cache creation tokens: {totals['cache_creation_input_tokens']:>12,}")
    print(f"  Cache read tokens:     {totals['cache_read_input_tokens']:>12,}")
    total_all = sum(totals.values())
    print(f"  Total all tokens:      {total_all:>12,}")
    print(f"  Assistant turns:       {len(turns):>12}")

    if not turns:
        print("\nNo assistant turns with usage data found.")
        return

    # Identify main vs sidechain turns
    main_turns = [t for t in turns if not t["sidechain"]]
    side_turns = [t for t in turns if t["sidechain"]]

    if side_turns:
        side_cache_read = sum(t["cache_read"] for t in side_turns)
        main_cache_read = sum(t["cache_read"] for t in main_turns)
        print(f"\n  Main thread turns:     {len(main_turns):>12}")
        print(f"  Sidechain turns:       {len(side_turns):>12}")
        print(f"  Main cache-read:       {main_cache_read:>12,}")
        print(f"  Sidechain cache-read:  {side_cache_read:>12,}")

    # Top 5 most expensive turns by total context
    print("\nTop 5 most expensive turns (by total context = input + cache_create + cache_read):")
    sorted_turns = sorted(turns, key=lambda t: t["total_context"], reverse=True)
    for t in sorted_turns[:5]:
        tag = " [sidechain]" if t["sidechain"] else ""
        print(f"  Turn {t['turn']:>3}: {t['total_context']:>10,} "
              f"(in={t['input']:,} cc={t['cache_create']:,} cr={t['cache_read']:,} "
              f"out={t['output']:,}){tag}")

    # Cache read distribution
    print("\nCache-read per turn (descending):")
    sorted_by_cr = sorted(turns, key=lambda t: t["cache_read"], reverse=True)
    for t in sorted_by_cr[:10]:
        tag = " [sidechain]" if t["sidechain"] else ""
        pct = (t["cache_read"] / totals["cache_read_input_tokens"] * 100
               if totals["cache_read_input_tokens"] > 0 else 0)
        print(f"  Turn {t['turn']:>3}: {t['cache_read']:>10,} ({pct:5.1f}%){tag}")

    print(f"\n=== End Analysis ===\n")
    print("Use this to compare sessions before/after agent-context changes.")
    print("Key metric: total cache-read tokens (drives usage limit burn).")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    if sys.argv[1] == "--list":
        project_dir = find_project_dir()
        list_sessions(project_dir)
        return

    jsonl_path = resolve_jsonl_path(sys.argv[1])
    totals, turns = analyze_session(jsonl_path)
    print_report(jsonl_path, totals, turns)


if __name__ == "__main__":
    main()
