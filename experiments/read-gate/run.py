#!/usr/bin/env python3
"""Run the read-gate experiment. See DESIGN.md.

Each session is a headless Claude Code run in a fresh copy of the fixtures.
One JSON record per session goes to results/ (or results/pilot/), holding
Claude Code's own output plus counts read from the session transcript.

Usage:
  run.py --claude PATH --arm-dir gate-v1=DIR --arm-dir gate-v2=DIR \
         --work DIR [--repeats 5] [--parallel 4] [--pilot]

Standard library only.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"
SEED = 20260928
BUDGET_USD = 30.0
MAX_TURNS = "25"
TIMEOUT_S = 900
HAIKU_IN, HAIKU_OUT = 1.00 / 1e6, 5.00 / 1e6

TASKS = {
    "single-file": (
        "Which functions in langsmith.ts (in this directory) call createRunTree, "
        "and with which run_type value in each call? End your answer with a JSON "
        "object in a ```json block that maps each function name to the list of "
        "run_type values it passes to createRunTree."
    ),
    "cross-file": (
        "For each of langsmith.ts, transcript.ts, stop.ts, and config.ts (in this "
        "directory), list the functions declared with `export function` or "
        "`export async function`. End your answer with a JSON object in a ```json "
        "block that maps each file name to the list of those function names, with "
        "an empty list for a file that has none."
    ),
    "edit": (
        "In langsmith.ts (in this directory), insert the line "
        "`// Closes or creates the Agent tool run.` immediately above the line "
        "`export async function closeAgentToolRun(options: {`, with no indentation. "
        "Change nothing else in the file."
    ),
}
ALLOWED_TOOLS = ["Read", "Edit", "Grep", "Glob", "Skill", "Bash(*bulk-read*)"]
WORKER_RE = re.compile(r"\[langsmith-shunt: \S+ read (\d+) tokens and (?:returned|wrote) (\d+)")
BLOCK_MARKERS = ("full reads of files over", "lines (limit", "-line limit", "for a full read")

spent_lock = threading.Lock()
spent = 0.0


def transcript_metrics(session_id: str) -> dict:
    paths = glob.glob(str(Path.home() / ".claude/projects/*" / f"{session_id}.jsonl"))
    m = {"transcript_found": bool(paths), "tool_calls": {}, "bash_commands": [],
         "blocked": 0, "bulk_reads": 0, "worker_in": 0, "worker_out": 0}
    if not paths:
        return m
    for line in open(paths[0]):
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                name = block.get("name", "?")
                m["tool_calls"][name] = m["tool_calls"].get(name, 0) + 1
                if name == "Bash":
                    cmd = (block.get("input") or {}).get("command", "")
                    m["bash_commands"].append(cmd[:300])
                    if "bulk-read" in cmd:
                        m["bulk_reads"] += 1
            elif block.get("type") == "tool_result":
                text = block.get("content")
                if isinstance(text, list):
                    text = " ".join(t.get("text", "") for t in text if isinstance(t, dict))
                text = str(text or "")
                if block.get("is_error") and any(k in text for k in BLOCK_MARKERS):
                    m["blocked"] += 1
                for tin, tout in WORKER_RE.findall(text):
                    m["worker_in"] += int(tin)
                    m["worker_out"] += int(tout)
    m["worker_cost_usd"] = m["worker_in"] * HAIKU_IN + m["worker_out"] * HAIKU_OUT
    return m


def run_one(job: dict, args, out_dir: Path) -> dict | None:
    global spent
    with spent_lock:
        if spent > BUDGET_USD:
            print(f"skip {job['run_id']}: budget of ${BUDGET_USD} reached", flush=True)
            return None

    work = Path(args.work) / job["run_id"]
    work.mkdir(parents=True)
    for f in FIXTURES.glob("*.ts"):
        shutil.copy(f, work / f.name)

    env = dict(os.environ, TRACE_TO_LANGSMITH="false", SHUNT_TRACE="false")
    if job["arm"] == "control":
        env["SHUNT_DISABLED"] = "1"
    cmd = [args.claude, "-p", TASKS[job["task"]], "--output-format", "json", "--max-turns", MAX_TURNS]
    plugin_dir = args.arm_dirs.get(job["arm"])
    if plugin_dir:
        cmd += ["--plugin-dir", plugin_dir]
    cmd += ["--allowedTools", *ALLOWED_TOOLS]

    started = time.time()
    try:
        proc = subprocess.run(cmd, cwd=work, env=env, capture_output=True, text=True, timeout=TIMEOUT_S)
        stdout, stderr, code = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired as e:
        partial = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        stdout, stderr, code = partial, "timeout", -1
    duration = time.time() - started

    try:
        output = json.loads(stdout)
    except json.JSONDecodeError:
        output = {"parse_error": True, "stdout_tail": stdout[-2000:]}

    record = {
        **job,
        "started": started,
        "duration_s": round(duration, 1),
        "exit_code": code,
        "stderr_tail": stderr[-1000:],
        "claude": {k: output.get(k) for k in (
            "session_id", "total_cost_usd", "num_turns", "usage", "modelUsage",
            "is_error", "subtype", "duration_ms", "result")},
        "metrics": transcript_metrics(output.get("session_id", "")) if output.get("session_id") else {},
    }
    if job["task"] == "edit":
        record["edited_file"] = (work / "langsmith.ts").read_text()

    cost = (output.get("total_cost_usd") or 0) + record["metrics"].get("worker_cost_usd", 0)
    with spent_lock:
        spent += cost
        total = spent
    (out_dir / f"{job['run_id']}.json").write_text(json.dumps(record, indent=2))
    print(f"done {job['order']:>2} {job['arm']:<8} {job['task']:<11} rep {job['rep']}  "
          f"${cost:.3f}  turns {output.get('num_turns')}  bulk-reads {record['metrics'].get('bulk_reads')}  "
          f"total ${total:.2f}", flush=True)
    return record


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--claude", required=True)
    p.add_argument("--arm-dir", action="append", default=[], help="arm=plugin dir")
    p.add_argument("--work", required=True, help="scratch directory for per-session copies")
    p.add_argument("--repeats", type=int, default=5)
    p.add_argument("--parallel", type=int, default=4)
    p.add_argument("--pilot", action="store_true", help="one edit run per arm, saved to results/pilot/")
    args = p.parse_args()
    args.arm_dirs = dict(a.split("=", 1) for a in args.arm_dir)
    for arm in ("gate-v1", "gate-v2"):
        if arm not in args.arm_dirs:
            sys.exit(f"--arm-dir {arm}=DIR is required")

    arms = ["control", "gate-v1", "gate-v2"]
    if args.pilot:
        jobs = [{"arm": a, "task": "edit", "rep": 0} for a in arms]
        out_dir = HERE / "results" / "pilot"
    else:
        jobs = [{"arm": a, "task": t, "rep": r} for a in arms for t in TASKS for r in range(1, args.repeats + 1)]
        random.Random(SEED).shuffle(jobs)
        out_dir = HERE / "results"
    out_dir.mkdir(parents=True, exist_ok=True)
    for i, job in enumerate(jobs, 1):
        job["order"] = i
        job["run_id"] = f"{job['arm']}--{job['task']}--{job['rep']}--{uuid.uuid4().hex[:8]}"
        job["plugin_dir"] = args.arm_dirs.get(job["arm"])

    print(f"{len(jobs)} sessions, {args.parallel} at a time, budget ${BUDGET_USD}", flush=True)
    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        list(pool.map(lambda j: run_one(j, args, out_dir), jobs))
    print(f"finished, total ${spent:.2f}", flush=True)


if __name__ == "__main__":
    main()
