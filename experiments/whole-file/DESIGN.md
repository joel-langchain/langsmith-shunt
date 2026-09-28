# Whole-file experiment: design

Written on 28 Sep 2026, before any run. The results are in [RESULTS.md](RESULTS.md).

## Question

The [read-gate experiment](../read-gate/RESULTS.md) found that the gate never fired: on lookup and edit tasks, Claude used Grep and short reads and never read a large file in full. This experiment tests the case the gate is meant for, tasks that need a whole file understood. It asks:

1. When the task needs whole files, does Claude try to read them in full, so the block fires?
2. When the block fires, does Claude delegate to `bulk-read`, or work round the block?
3. Does either gate arm lower the cost per task compared with no gate, without lowering answer quality?
4. Does telling Claude to "read" the files change any of the above?

## Factors

- **Arm**, 3 levels, the same as the read-gate experiment: `control` (no plugin), `gate-v1` (langsmith-shunt at `4e56bfe`, v0.1.2), and `gate-v2` (langsmith-shunt at `67c2981`, v0.1.3, the directive message).
- **Task**, 2 levels, both on the same four fixture files as before:
  - `one-file`: summarise `langsmith.ts` (1,227 lines).
  - `four-file`: summarise how `langsmith.ts`, `transcript.ts`, `stop.ts`, and `config.ts` work together (2,533 lines).
- **Wording**, 2 levels:
  - `neutral`: "Summarise what X does ..."
  - `read`: "Read X and summarise what it does ..."

This gives 3 × 2 × 2 = 12 cells, with 5 repeats each, 60 sessions. The number of repeats is fixed here. The full prompts are in `run.py`.

## Procedure

It's the same as the read-gate experiment, using its runner unchanged:

- a fresh copy of the fixtures for each session;
- headless `claude -p` with the default model and settings;
- `--allowedTools Read Edit Grep Glob Skill "Bash(*bulk-read*)"` in every arm;
- LangSmith tracing and delegation runs switched off;
- Claude Haiku 4.5 as the worker through the LangSmith Gateway;
- order shuffled with a fixed seed (2026092802), and 4 sessions at a time.

The budget guard is $40.

## Measures

- **Primary: cost per completed task**, in USD. Claude Code's `total_cost_usd`, plus the worker's tokens at Claude Haiku 4.5 list price ($1 and $5 per million input and output tokens).
- **Quality: fact coverage**, the share of a fixed checklist of facts from the files that the summary states. A fact counts when every pattern in its row matches the answer, case-insensitive. The checklist is in `analyze.py`: 8 facts for `one-file`, 10 for `four-file`. It measures coverage of the named facts, not accuracy or writing.
- Secondary: turns, full reads attempted, whether the block fired, whether and how often Claude called `bulk-read`, and worker tokens.

## Analysis and decision rule

For each task × wording and each gate arm, the difference in mean cost from `control` in the same task × wording, with a 95% bootstrap interval (10,000 resamples, fixed seed).

- A gate arm **saves** there if the whole interval is below zero and its mean coverage is within 0.10 of control.
- It **costs more** if the whole interval is above zero.
- Otherwise the result is **inconclusive**.

Questions 1 and 2 are answered descriptively, from counts of full reads, blocks, and `bulk-read` calls.

## Known limits

- These are the limits carried over from the read-gate experiment: one codebase, one model, five repeats per cell, and a large base context from the plugins installed on this machine.
- A keyword checklist can miss a fact stated in other words, or credit a passing mention. The bias is the same in every arm. The answers are saved, so they can be regraded with a different method.
- The worker model writes the summary content in delegated runs. Coverage then reflects Haiku's reading of the file as passed on by Claude.
