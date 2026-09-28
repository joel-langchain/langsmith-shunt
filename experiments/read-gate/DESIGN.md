# Read-gate experiment: design

Written on 28 Sep 2026, before any run. The results are in [RESULTS.md](RESULTS.md).

## Question

Does blocking full reads of large files, and pointing Claude at a cheaper worker model, lower the cost of a whole Claude Code task without lowering the quality of the result?

A pilot on 28 Sep (one run per arm, one question) found the opposite. With the block on, Claude worked around it with grep and sed over 8 turns ($0.40), where the control read the file and finished in 4 turns ($0.17). This experiment tests that with repeats, three task types, and a second block message.

## Arms

| Arm | Plugin | Block message |
| --- | --- | --- |
| `control` | Not loaded (`SHUNT_DISABLED=1` as well) | None |
| `gate-v1` | langsmith-shunt at commit `4e56bfe` (v0.1.2) | Names the bulk-reader skill, and suggests Read with offset and limit for edits |
| `gate-v2` | langsmith-shunt v0.1.3 | Gives the exact `bulk-read` command, says not to read the file in parts with Read, grep, or sed, and keeps offset and limit for edits only |

## Tasks

All tasks run on four files from LangChain's MIT-licensed `langsmith-tracing` plugin, version 0.3.1 (`fixtures/`). All four are over the 350-line limit.

| Task | Prompt (short form) | Answer key | Score |
| --- | --- | --- | --- |
| `single-file` | Which functions in `langsmith.ts` call `createRunTree`, and with which `run_type` in each call. End with a JSON object. | 7 (function, run_type) pairs across 5 functions | F1 over pairs |
| `cross-file` | For each of `langsmith.ts`, `transcript.ts`, `stop.ts`, and `config.ts`, list the functions declared with `export function` or `export async function`. End with a JSON object. | 28 (file, function) pairs; `stop.ts` has none | F1 over pairs |
| `edit` | Insert one given comment line directly above the `closeAgentToolRun` declaration in `langsmith.ts`, changing nothing else. | The original file with that one line added | 1 if the file matches exactly, else 0 |

The full prompts and keys are in `run.py` and `analyze.py`.

## Procedure

- 3 arms × 3 tasks × 5 repeats = 45 sessions. The number of repeats is fixed here and will not be extended after seeing results.
- Order is shuffled with a fixed seed, and 4 sessions run at a time, so time-of-day and load effects spread across arms.
- Each session runs headless (`claude -p`) in a fresh copy of the fixtures, with Claude Code's default model and settings on this machine, and with `--allowedTools Read Edit Grep Glob Skill "Bash(*bulk-read*)"` in every arm.
- LangSmith tracing and delegation runs are switched off (`TRACE_TO_LANGSMITH=false`, `SHUNT_TRACE=false`), so the experiment writes nothing to shared projects. All measures come from Claude Code's JSON output and the session transcript.
- The worker model is Claude Haiku 4.5 through the LangSmith LLM Gateway, using Claude Code's own gateway settings.
- 3 pilot sessions (one per arm, `edit` task) check the harness first and are left out of the analysis.
- A budget guard stops new sessions once the running total passes $30.

## Measures

- **Primary: cost per completed task**, in USD. Claude Code's reported `total_cost_usd`, plus the worker's tokens at Claude Haiku 4.5 list price ($1 per million input tokens, $5 per million output tokens).
- Secondary: quality score, turns, wall time, whether the block fired, whether Claude called `bulk-read`, and how often.

## Analysis and decision rule

For each task and gate arm, the difference in mean cost from `control`, with a 95% bootstrap interval (10,000 resamples, fixed seed).

- A gate arm **saves** on a task if the whole interval is below zero and its mean quality is within 0.05 of control (for `edit`, no more than one of five runs fails that control passes).
- It **costs more** if the whole interval is above zero.
- Otherwise the result is **inconclusive** at this sample size.

## Known limits

- Five repeats per cell detect large differences only. The pilot difference was about 2.4 times; smaller effects may show as inconclusive.
- One codebase, one model, and three tasks. The files are 367 to 1,227 lines. Much larger files would favour the gate more.
- The base context in these sessions includes every skill and plugin installed on this machine, so it is larger than a clean install. That makes each extra turn dearer and works against the gate.
- The quality scores check the facts asked for, not the wording of the answer.
