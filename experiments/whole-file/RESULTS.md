# Whole-file experiment: results

Run on 28 Sep 2026 to the design in [DESIGN.md](DESIGN.md), which was committed before the run (`7b91169`). 60 sessions, $15.18 in total. Claude Code 2.1.281, main model `claude-opus-5-5[1m]`, worker model Claude Haiku 4.5 through the LangSmith Gateway.

## Result

When the task needed whole files, the gate saved money.

- **Control.** Without the plugin, Claude read the files in full in all 20 control sessions.
- **Gate arms.** With the plugin, Claude delegated to `bulk-read` in all 40 gate sessions.
- **One file.** A summary of one 1,227-line file cost 13 to 20% less in both gate arms, with the same fact coverage. That meets the pre-registered rule for "saves" in all four comparisons.
- **Four files.** A summary of four files (2,533 lines) cost 18 to 32% less on average. By the pre-registered rule the verdict is inconclusive, because the intervals are wide and one arm lost fact coverage.

| Task and wording | Arm | Cost per task, mean (95% CI) | Turns | Fact coverage | Runs blocked | Runs that delegated |
| --- | --- | --- | --- | --- | --- | --- |
| one-file, neutral | control | $0.212 ($0.211 to $0.212) | 2.0 | 1.00 | 0/5 | 0/5 |
| one-file, neutral | gate-v1 | $0.184 ($0.173 to $0.192) | 5.6 | 0.95 | 0/5 | 5/5 |
| one-file, neutral | gate-v2 | $0.181 ($0.167 to $0.202) | 5.4 | 1.00 | 0/5 | 5/5 |
| one-file, read | control | $0.210 ($0.209 to $0.211) | 2.0 | 1.00 | 0/5 | 0/5 |
| one-file, read | gate-v1 | $0.168 ($0.166 to $0.170) | 5.0 | 1.00 | 1/5 | 5/5 |
| one-file, read | gate-v2 | $0.167 ($0.166 to $0.169) | 4.2 | 1.00 | 2/5 | 5/5 |
| four-file, neutral | control | $0.368 ($0.363 to $0.374) | 6.0 | 0.96 | 0/5 | 0/5 |
| four-file, neutral | gate-v1 | $0.296 ($0.254 to $0.369) | 6.2 | 0.92 | 0/5 | 5/5 |
| four-file, neutral | gate-v2 | $0.251 ($0.243 to $0.260) | 6.6 | 0.84 | 0/5 | 5/5 |
| four-file, read | control | $0.392 ($0.350 to $0.475) | 5.0 | 1.00 | 0/5 | 0/5 |
| four-file, read | gate-v1 | $0.285 ($0.219 to $0.382) | 5.8 | 0.92 | 1/5 | 5/5 |
| four-file, read | gate-v2 | $0.322 ($0.273 to $0.378) | 6.8 | 0.90 | 3/5 | 5/5 |

| Task and wording | Arm | Cost difference from control, mean (95% CI) | Ratio | Coverage within 0.10 | Verdict |
| --- | --- | --- | --- | --- | --- |
| one-file, neutral | gate-v1 | −$0.028 (−$0.038 to −$0.020) | 0.87 | yes | saves |
| one-file, neutral | gate-v2 | −$0.031 (−$0.045 to −$0.010) | 0.86 | yes | saves |
| one-file, read | gate-v1 | −$0.042 (−$0.044 to −$0.040) | 0.80 | yes | saves |
| one-file, read | gate-v2 | −$0.043 (−$0.045 to −$0.041) | 0.80 | yes | saves |
| four-file, neutral | gate-v1 | −$0.072 (−$0.115 to +$0.002) | 0.81 | yes | inconclusive |
| four-file, neutral | gate-v2 | −$0.117 (−$0.126 to −$0.107) | 0.68 | no (0.84 vs 0.96) | inconclusive |
| four-file, read | gate-v1 | −$0.107 (−$0.217 to +$0.002) | 0.73 | yes | inconclusive |
| four-file, read | gate-v2 | −$0.070 (−$0.166 to +$0.013) | 0.82 | yes | inconclusive |

Per-session data is in `results/`. To regrade, run `python3 analyze.py`.

## Answers to the design's questions

**1. Does Claude try to read whole files, so the block fires?** Rarely. The block fired in 7 of 40 gate sessions, all with "read" wording. With neutral wording it never fired, because Claude used the bulk-reader skill before trying a full read.

**2. When the block fires, does Claude delegate or work round it?** It delegated in all 7 blocked sessions. After a v2 block, Claude called `bulk-read` directly in all 5 cases, using the command in the message. After a v1 block, Claude loaded the skill first in both cases.

**3. Does the gate lower cost without lowering quality?** For one file, yes: 13 to 20% lower, with coverage of 0.95 to 1.00 against control's 1.00. For four files, the mean cost was 18 to 32% lower. Coverage fell from 0.96 to 1.00 to between 0.84 and 0.92, and the pre-registered verdict is inconclusive.

**4. Does "read" wording change this?** It made full-read attempts, and so blocks, more likely. Its effect on cost and coverage was small and not consistent across tasks. For one file, read wording was about $0.015 cheaper in both gate arms. For four files, the direction differed by arm.

## What drove the delegation

In most gate sessions the skill did the work, not the hook. The bulk-reader skill's description ("Use for files over 350 lines ... or summarising") was enough for Claude to call it without being blocked.

| Wording | Gate sessions | Blocked first | Delegated through the skill | Called `bulk-read` directly |
| --- | --- | --- | --- | --- |
| neutral | 20 | 0 | 20 | 0 |
| read | 20 | 7 | 15 | 5 (all after a v2 block) |

Because the block so rarely fired, v1 and v2 differ only in those 7 sessions, and their cost differences here are mostly noise.

## Where the saving comes from

A full read puts the file into Claude's context, and the first time that context is sent it's written to the prompt cache. At Claude Opus 5.5 list prices, a cache write costs $5 per million tokens, a cache read $0.20, and output $20. Rebuilding the one-file costs from the token counts gives Claude Code's reported cost exactly:

| One-file, neutral | Cache reads | Cache writes | Output | Claude cost | Worker cost | Total |
| --- | --- | --- | --- | --- | --- | --- |
| control | 95,410 → $0.019 | 29,599 → $0.148 | 2,227 → $0.045 | $0.212 | none | $0.212 |
| gate-v1 | 235,141 → $0.047 | 13,114 → $0.066 | 2,180 → $0.044 | $0.156 | $0.028 | $0.184 |

The control's largest cost is writing the file into the cache: about 16,500 tokens more than the gate arm, which is $0.082. The gate replaces that with the worker's cost ($0.028) and three to four extra turns, each re-reading cached context at a twenty-fifth of the write price ($0.028 in total). The difference is the saving.

This also explains the read-gate experiment. There, Claude never put a whole file into context, so there was no large cache write for the gate to avoid.

## Quality

Fact coverage for one file was the same in all arms. For four files, the gate arms dropped specific details more often. Delegated summaries go through two steps, Haiku's answer and then Claude's summary of it.

| Four-file cell | Facts missed, in 5 runs |
| --- | --- |
| neutral, control | dotted order ×2 |
| neutral, gate-v1 | dotted order ×3, streams large files ×1 |
| neutral, gate-v2 | turns are chain runs ×4, dotted order ×2, git details ×1, streams large files ×1 |
| read, control | none |
| read, gate-v1 | turns are chain runs ×2, dotted order ×2 |
| read, gate-v2 | turns are chain runs ×2, dotted order ×1, streams large files ×1, reads JSONL ×1 |

The checklist looks for fixed words. A summary that says "a root run per turn" without "chain" is scored as missing that fact, so these counts show how much specific detail came through, not whether the summary was wrong.

## Sensitivity check (not pre-registered)

The first four sessions started with a cold cache, so each also paid to write the base context. All four were four-file cells, one control and three gate:

- The three gate sessions wrote 58,000 to 62,000 tokens to the cache, against 17,000 to 21,000 on average for the other sessions in their cells.
- The control session wrote 96,000, against about 52,000 for the others in its cell.

Leaving the four out gives:

| Task and wording | Arm | n | Cost difference from control (95% CI) | Ratio |
| --- | --- | --- | --- | --- |
| four-file, neutral | gate-v1 | 4 | −$0.108 (−$0.119 to −$0.096) | 0.71 |
| four-file, neutral | gate-v2 | 5 | −$0.117 (−$0.126 to −$0.107) | 0.68 |
| four-file, read | gate-v1 | 4 | −$0.113 (−$0.142 to −$0.081) | 0.68 |
| four-file, read | gate-v2 | 4 | −$0.053 (−$0.088 to −$0.015) | 0.85 |

Without the warm-up sessions, every four-file interval is below zero, at 15 to 32% lower cost. This analysis was chosen after seeing the data, so the pre-registered verdicts above stand as the result. It suggests the four-file cost saving is real, and that the open question for four files is quality rather than cost.

## Both experiments together

| Kind of task | Does Claude read large files whole without the gate? | Effect of the gate |
| --- | --- | --- |
| Lookup or edit ([read-gate](../read-gate/RESULTS.md), 45 sessions) | No. Grep and short reads | None. Cost within a few cents, all answers correct |
| Summary of one file (this experiment) | Yes, every time | 13 to 20% cheaper, same fact coverage |
| Summary of four files (this experiment) | Yes, every time | 18 to 32% cheaper on average. Some specific detail lost. Inconclusive by the pre-registered rule |

## Limits

- One codebase, one main model, one Claude Code version, files of 367 to 1,227 lines, and 5 repeats per cell.
- The base context on this machine is large (many plugins and skills). A smaller one would make the file a larger share of each session.
- Fact coverage uses fixed keywords, not a judgement of accuracy.
- There was no arm with the skill but not the hook. Since the skill drove most of the delegation, that arm would show how much the hook adds.
