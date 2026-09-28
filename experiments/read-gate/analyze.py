#!/usr/bin/env python3
"""Grade and summarise the read-gate runs. See DESIGN.md for the rules.

Reads results/*.json (not results/pilot/), writes results/summary.json and
results/summary.md, and prints the markdown.

Standard library only.
"""

from __future__ import annotations

import json
import random
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
SEED = 20260928
RESAMPLES = 10_000
ARMS = ["control", "gate-v1", "gate-v2"]
TASKS = ["single-file", "cross-file", "edit"]

SINGLE_FILE_KEY = {
    ("traceTurn", "chain"), ("traceTurn", "llm"), ("traceTurn", "tool"),
    ("patchTurnRun", "chain"), ("tracePendingSubagents", "tool"),
    ("traceSubagentChain", "chain"), ("closeAgentToolRun", "tool"),
}
CROSS_FILE_KEY = {
    ("langsmith.ts", n) for n in (
        "initTracing flushPendingTraces generateDottedOrderSegment parseDottedOrder traceTurn "
        "turnIdentityFromOpenTurn completeTurnRun closeTurnRun closeInterruptedTurn "
        "tracePendingSubagents traceWorkflowStage closeAgentToolRun").split()
} | {
    ("transcript.ts", n) for n in (
        "readTranscript getTranscriptEndLine readRuntimeVersion isHumanMessage isToolResult "
        "isAssistantMessage stripModelDateSuffix resolveProvider completedToolUseIds groupIntoTurns").split()
} | {
    ("config.ts", n) for n in
    "readAnthropicUserId readLocalUsername parseRepoName getRepoName getGitInfo loadConfig".split()
}
EDIT_LINE = "// Closes or creates the Agent tool run."
EDIT_ANCHOR = "export async function closeAgentToolRun(options: {"


def expected_edit() -> str:
    original = (HERE / "fixtures" / "langsmith.ts").read_text()
    lines = original.split("\n")
    i = lines.index(EDIT_ANCHOR)
    return "\n".join(lines[:i] + [EDIT_LINE] + lines[i:])


def last_json(text: str):
    blocks = re.findall(r"```json\s*(.*?)```", text or "", flags=re.S)
    for block in reversed(blocks):
        try:
            return json.loads(block)
        except json.JSONDecodeError:
            continue
    return None


def f1(found: set, key: set) -> float:
    if not found:
        return 0.0
    tp = len(found & key)
    if tp == 0:
        return 0.0
    precision, recall = tp / len(found), tp / len(key)
    return 2 * precision * recall / (precision + recall)


def grade(record: dict, edit_target: str) -> float:
    task = record["task"]
    if task == "edit":
        return 1.0 if record.get("edited_file") == edit_target else 0.0
    obj = last_json((record.get("claude") or {}).get("result") or "")
    if not isinstance(obj, dict):
        return 0.0
    found = set()
    for k, values in obj.items():
        values = values if isinstance(values, list) else [values]
        for v in values:
            if task == "single-file":
                found.add((str(k).strip(), str(v).strip().strip('"').lower()))
            else:
                found.add((Path(str(k)).name, str(v).strip().removesuffix("()")))
    return f1(found, SINGLE_FILE_KEY if task == "single-file" else CROSS_FILE_KEY)


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def boot_mean(xs, rng):
    return [mean([rng.choice(xs) for _ in xs]) for _ in range(RESAMPLES)]


def interval(samples):
    s = sorted(samples)
    return s[int(0.025 * len(s))], s[int(0.975 * len(s)) - 1]


def main() -> None:
    edit_target = expected_edit()
    records = [json.loads(p.read_text()) for p in sorted(RESULTS.glob("*.json")) if p.name != "summary.json"]
    rows = []
    for r in records:
        c = r.get("claude") or {}
        m = r.get("metrics") or {}
        rows.append({
            "arm": r["arm"], "task": r["task"], "rep": r["rep"],
            "cost": (c.get("total_cost_usd") or 0) + m.get("worker_cost_usd", 0),
            "claude_cost": c.get("total_cost_usd") or 0,
            "worker_cost": m.get("worker_cost_usd", 0),
            "turns": c.get("num_turns") or 0,
            "duration_s": r.get("duration_s"),
            "quality": grade(r, edit_target),
            "blocked": m.get("blocked", 0),
            "bulk_reads": m.get("bulk_reads", 0),
            "failed": bool(c.get("is_error")) or r.get("exit_code") != 0,
        })

    rng = random.Random(SEED)
    cells, effects = {}, []
    for task in TASKS:
        control_costs = [x["cost"] for x in rows if x["task"] == task and x["arm"] == "control"]
        control_boot = boot_mean(control_costs, rng) if control_costs else []
        for arm in ARMS:
            xs = [x for x in rows if x["task"] == task and x["arm"] == arm]
            if not xs:
                continue
            costs = [x["cost"] for x in xs]
            boot = boot_mean(costs, rng)
            cells[(task, arm)] = {
                "n": len(xs),
                "cost_mean": mean(costs),
                "cost_ci": interval(boot),
                "claude_cost_mean": mean([x["claude_cost"] for x in xs]),
                "worker_cost_mean": mean([x["worker_cost"] for x in xs]),
                "turns_mean": mean([x["turns"] for x in xs]),
                "duration_mean": mean([x["duration_s"] or 0 for x in xs]),
                "quality_mean": mean([x["quality"] for x in xs]),
                "quality_passes": sum(1 for x in xs if x["quality"] == 1.0),
                "blocked_runs": sum(1 for x in xs if x["blocked"]),
                "delegated_runs": sum(1 for x in xs if x["bulk_reads"]),
                "bulk_reads_mean": mean([x["bulk_reads"] for x in xs]),
                "failed_runs": sum(1 for x in xs if x["failed"]),
            }
            if arm != "control" and control_boot:
                diff = [a - b for a, b in zip(boot, control_boot)]
                lo, hi = interval(diff)
                c, g = cells[(task, "control")], cells[(task, arm)]
                if task == "edit":
                    quality_ok = g["quality_passes"] >= c["quality_passes"] - 1
                else:
                    quality_ok = g["quality_mean"] >= c["quality_mean"] - 0.05
                if hi < 0 and quality_ok:
                    verdict = "saves"
                elif lo > 0:
                    verdict = "costs more"
                else:
                    verdict = "inconclusive"
                effects.append({
                    "task": task, "arm": arm,
                    "diff_mean": g["cost_mean"] - c["cost_mean"],
                    "diff_ci": (lo, hi),
                    "ratio": g["cost_mean"] / c["cost_mean"] if c["cost_mean"] else float("nan"),
                    "quality_ok": quality_ok, "verdict": verdict,
                })

    lines = ["## Cost and behaviour by task and arm", "",
             "| Task | Arm | n | Cost per task, mean (95% CI) | Claude | Worker | Turns | Quality | Blocked runs | Runs that delegated | Failed |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for (task, arm), c in cells.items():
        lo, hi = c["cost_ci"]
        q = f"{c['quality_passes']}/{c['n']} pass" if task == "edit" else f"{c['quality_mean']:.2f} F1"
        lines.append(
            f"| {task} | {arm} | {c['n']} | ${c['cost_mean']:.3f} (${lo:.3f} to ${hi:.3f}) | "
            f"${c['claude_cost_mean']:.3f} | ${c['worker_cost_mean']:.4f} | {c['turns_mean']:.1f} | {q} | "
            f"{c['blocked_runs']}/{c['n']} | {c['delegated_runs']}/{c['n']} | {c['failed_runs']} |")
    lines += ["", "## Difference from control", "",
              "| Task | Arm | Cost difference, mean (95% CI) | Ratio to control | Quality within margin | Verdict |",
              "| --- | --- | --- | --- | --- | --- |"]
    for e in effects:
        lo, hi = e["diff_ci"]
        lines.append(f"| {e['task']} | {e['arm']} | {e['diff_mean']:+.3f} ({lo:+.3f} to {hi:+.3f}) | "
                     f"{e['ratio']:.2f} | {'yes' if e['quality_ok'] else 'no'} | {e['verdict']} |")
    total = sum(x["cost"] for x in rows)
    lines += ["", f"{len(rows)} sessions, total cost ${total:.2f}."]
    md = "\n".join(lines) + "\n"
    (RESULTS / "summary.md").write_text(md)
    (RESULTS / "summary.json").write_text(json.dumps({
        "rows": rows,
        "cells": {f"{t}|{a}": v for (t, a), v in cells.items()},
        "effects": effects,
    }, indent=2))
    print(md)


if __name__ == "__main__":
    main()
