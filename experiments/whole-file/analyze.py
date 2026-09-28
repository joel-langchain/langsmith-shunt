#!/usr/bin/env python3
"""Grade and summarise the whole-file runs. See DESIGN.md for the rules.

Reads results/*.json, writes results/summary.json and results/summary.md,
and prints the markdown. Standard library only.
"""

from __future__ import annotations

import json
import random
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
SEED = 2026092802
RESAMPLES = 10_000
ARMS = ["control", "gate-v1", "gate-v2"]
CELLS = ["one-file-neutral", "one-file-read", "four-file-neutral", "four-file-read"]

# Each fact is a list of patterns that must all match the answer (case-insensitive).
ONE_FILE_FACTS = {
    "turns are chain runs": [r"\bturns?\b", r"\bchain\b"],
    "assistant calls are llm runs": [r"\bllm\b", r"assistant|model (call|response)|llm call"],
    "tool calls are tool runs": [r"\btool\b.{0,20}\b(run|call|use)s?\b|tool_use"],
    "subagents": [r"sub-?agents?"],
    "workflow stages": [r"workflow"],
    "dotted order": [r"dotted"],
    "flushing pending traces": [r"flush"],
    "interrupted turns": [r"interrupt"],
}
FOUR_FILE_FACTS = {
    "langsmith.ts: turns are chain runs": [r"\bturns?\b", r"\bchain\b"],
    "langsmith.ts: subagents": [r"sub-?agents?"],
    "langsmith.ts: dotted order": [r"dotted"],
    "transcript.ts: reads JSONL transcripts": [r"jsonl"],
    "transcript.ts: groups messages into turns": [r"group", r"\bturns?\b"],
    "transcript.ts: streams large files": [r"stream|chunk|large (transcript|file)s?"],
    "stop.ts: runs as the Stop hook": [r"stop hook|\bstop\b.{0,40}\bhook\b|\bhook\b.{0,40}\bstop\b"],
    "stop.ts: tracks state between runs": [r"\bstate\b|since (the )?last|new messages|last (processed|line)"],
    "config.ts: git repo, branch, or commit": [r"\bgit\b", r"branch|remote|repo|commit|sha"],
    "config.ts: user identity": [r"user ?id|username|anthropic user|hashed user"],
}


def coverage(text: str, facts: dict) -> tuple[float, list[str]]:
    hit = [name for name, pats in facts.items()
           if all(re.search(p, text or "", flags=re.I | re.S) for p in pats)]
    return len(hit) / len(facts), hit


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def boot_mean(xs, rng):
    return [mean([rng.choice(xs) for _ in xs]) for _ in range(RESAMPLES)]


def interval(samples):
    s = sorted(samples)
    return s[int(0.025 * len(s))], s[int(0.975 * len(s)) - 1]


def main() -> None:
    records = [json.loads(p.read_text()) for p in sorted(RESULTS.glob("*.json")) if p.name != "summary.json"]
    rows = []
    for r in records:
        c, m = r.get("claude") or {}, r.get("metrics") or {}
        facts = ONE_FILE_FACTS if r["task"].startswith("one-file") else FOUR_FILE_FACTS
        score, hit = coverage(c.get("result") or "", facts)
        rows.append({
            "arm": r["arm"], "cell": r["task"], "rep": r["rep"],
            "cost": (c.get("total_cost_usd") or 0) + m.get("worker_cost_usd", 0),
            "claude_cost": c.get("total_cost_usd") or 0,
            "worker_cost": m.get("worker_cost_usd", 0),
            "turns": c.get("num_turns") or 0,
            "coverage": score, "facts_hit": hit,
            "full_reads": m.get("full_reads", 0),
            "blocked": m.get("blocked", 0),
            "bulk_reads": m.get("bulk_reads", 0),
            "worker_in": m.get("worker_in", 0),
            "failed": bool(c.get("is_error")) or r.get("exit_code") != 0,
            "result_chars": len(c.get("result") or ""),
        })

    rng = random.Random(SEED)
    cells, effects = {}, []
    for cell in CELLS:
        control = [x["cost"] for x in rows if x["cell"] == cell and x["arm"] == "control"]
        control_boot = boot_mean(control, rng) if control else []
        for arm in ARMS:
            xs = [x for x in rows if x["cell"] == cell and x["arm"] == arm]
            if not xs:
                continue
            boot = boot_mean([x["cost"] for x in xs], rng)
            cells[(cell, arm)] = s = {
                "n": len(xs),
                "cost_mean": mean([x["cost"] for x in xs]),
                "cost_ci": interval(boot),
                "claude_cost_mean": mean([x["claude_cost"] for x in xs]),
                "worker_cost_mean": mean([x["worker_cost"] for x in xs]),
                "turns_mean": mean([x["turns"] for x in xs]),
                "coverage_mean": mean([x["coverage"] for x in xs]),
                "runs_full_read": sum(1 for x in xs if x["full_reads"]),
                "runs_blocked": sum(1 for x in xs if x["blocked"]),
                "runs_delegated": sum(1 for x in xs if x["bulk_reads"]),
                "bulk_reads_mean": mean([x["bulk_reads"] for x in xs]),
                "failed_runs": sum(1 for x in xs if x["failed"]),
            }
            if arm != "control" and control_boot:
                diff = [a - b for a, b in zip(boot, control_boot)]
                lo, hi = interval(diff)
                c = cells[(cell, "control")]
                quality_ok = s["coverage_mean"] >= c["coverage_mean"] - 0.10
                verdict = "saves" if hi < 0 and quality_ok else "costs more" if lo > 0 else "inconclusive"
                effects.append({"cell": cell, "arm": arm, "diff_mean": s["cost_mean"] - c["cost_mean"],
                                "diff_ci": (lo, hi), "ratio": s["cost_mean"] / c["cost_mean"],
                                "quality_ok": quality_ok, "verdict": verdict})

    lines = ["## Cost and behaviour by cell", "",
             "| Task and wording | Arm | n | Cost per task, mean (95% CI) | Claude | Worker | Turns | Fact coverage | Runs with a full read | Runs blocked | Runs that delegated | Failed |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for (cell, arm), s in cells.items():
        lo, hi = s["cost_ci"]
        lines.append(f"| {cell} | {arm} | {s['n']} | ${s['cost_mean']:.3f} (${lo:.3f} to ${hi:.3f}) | "
                     f"${s['claude_cost_mean']:.3f} | ${s['worker_cost_mean']:.4f} | {s['turns_mean']:.1f} | "
                     f"{s['coverage_mean']:.2f} | {s['runs_full_read']}/{s['n']} | {s['runs_blocked']}/{s['n']} | "
                     f"{s['runs_delegated']}/{s['n']} | {s['failed_runs']} |")
    lines += ["", "## Difference from control", "",
              "| Task and wording | Arm | Cost difference, mean (95% CI) | Ratio to control | Coverage within margin | Verdict |",
              "| --- | --- | --- | --- | --- | --- |"]
    for e in effects:
        lo, hi = e["diff_ci"]
        lines.append(f"| {e['cell']} | {e['arm']} | {e['diff_mean']:+.3f} ({lo:+.3f} to {hi:+.3f}) | "
                     f"{e['ratio']:.2f} | {'yes' if e['quality_ok'] else 'no'} | {e['verdict']} |")
    lines += ["", f"{len(rows)} sessions, total cost ${sum(x['cost'] for x in rows):.2f}."]
    md = "\n".join(lines) + "\n"
    (RESULTS / "summary.md").write_text(md)
    (RESULTS / "summary.json").write_text(json.dumps(
        {"rows": rows, "cells": {f"{c}|{a}": v for (c, a), v in cells.items()}, "effects": effects}, indent=2))
    print(md)


if __name__ == "__main__":
    main()
