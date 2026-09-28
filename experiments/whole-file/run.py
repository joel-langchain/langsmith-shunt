#!/usr/bin/env python3
"""Run the whole-file experiment. See DESIGN.md.

Reuses the read-gate runner (../read-gate/run.py) unchanged, with this
experiment's tasks, seed, budget, and output directory. Each record also
gets the number of full reads (Read with no offset or limit) and the
lengths of partial reads.

Usage: run.py --claude PATH --arm-dir gate-v1=DIR --arm-dir gate-v2=DIR --work DIR
"""

from __future__ import annotations

import glob
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("harness", HERE.parent / "read-gate" / "run.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)

FILES_ONE = "langsmith.ts (in this directory)"
FILES_FOUR = "langsmith.ts, transcript.ts, stop.ts, and config.ts (in this directory)"
ASK_ONE = "its purpose, the main functions, and how they fit together."
ASK_FOUR = "what each file does and how data flows between them."

harness.HERE = HERE
harness.FIXTURES = HERE.parent / "read-gate" / "fixtures"
harness.SEED = 2026092802
harness.BUDGET_USD = 40.0
harness.TASKS = {
    "one-file-neutral": f"Summarise what {FILES_ONE} does: {ASK_ONE}",
    "one-file-read": f"Read {FILES_ONE} and summarise what it does: {ASK_ONE}",
    "four-file-neutral": f"Summarise how {FILES_FOUR} work together: {ASK_FOUR}",
    "four-file-read": f"Read {FILES_FOUR} and summarise how they work together: {ASK_FOUR}",
}

base_metrics = harness.transcript_metrics


def transcript_metrics(session_id: str) -> dict:
    m = base_metrics(session_id)
    m["full_reads"], m["partial_read_limits"] = 0, []
    for path in glob.glob(str(Path.home() / ".claude/projects/*" / f"{session_id}.jsonl")):
        for line in open(path):
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            for block in (rec.get("message") or {}).get("content") or []:
                if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "Read":
                    inp = block.get("input") or {}
                    if "offset" in inp or "limit" in inp:
                        m["partial_read_limits"].append(inp.get("limit"))
                    else:
                        m["full_reads"] += 1
    return m


harness.transcript_metrics = transcript_metrics

if __name__ == "__main__":
    harness.main()
