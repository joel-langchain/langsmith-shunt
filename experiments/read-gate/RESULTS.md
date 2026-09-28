# Read-gate experiment: results

Run on 28 Sep 2026 to the design in [DESIGN.md](DESIGN.md), which was committed before the run (`67c2981`). 45 sessions, $5.27 in total. Claude Code 2.1.281, main model `claude-opus-5-5[1m]`, worker model Claude Haiku 4.5.

## Result

The block never fired. In all 45 sessions Claude never tried to read one of the large files in full, so the gate had nothing to redirect, and no session called `bulk-read`. Claude found what it needed with Grep and with reads of 5 to 350 lines. Cost per task was within a few cents across arms, and every answer was correct.

By the design's decision rule, every comparison is inconclusive. The intervals are narrow, so on these tasks any effect of the gate is at most a few cents per task.

| Task | Arm | Cost per task, mean (95% CI) | Turns | Quality | Blocked runs | Runs that delegated |
| --- | --- | --- | --- | --- | --- | --- |
| single-file | control | $0.119 ($0.110 to $0.126) | 3.2 | 1.00 F1 | 0/5 | 0/5 |
| single-file | gate-v1 | $0.139 ($0.113 to $0.168) | 3.8 | 1.00 F1 | 0/5 | 0/5 |
| single-file | gate-v2 | $0.125 ($0.114 to $0.139) | 3.6 | 1.00 F1 | 0/5 | 0/5 |
| cross-file | control | $0.115 ($0.109 to $0.120) | 4.4 | 1.00 F1 | 0/5 | 0/5 |
| cross-file | gate-v1 | $0.119 ($0.113 to $0.126) | 4.6 | 1.00 F1 | 0/5 | 0/5 |
| cross-file | gate-v2 | $0.112 ($0.108 to $0.118) | 4.0 | 1.00 F1 | 0/5 | 0/5 |
| edit | control | $0.108 ($0.103 to $0.113) | 4.0 | 5/5 pass | 0/5 | 0/5 |
| edit | gate-v1 | $0.110 ($0.109 to $0.111) | 4.0 | 5/5 pass | 0/5 | 0/5 |
| edit | gate-v2 | $0.108 ($0.103 to $0.113) | 4.0 | 5/5 pass | 0/5 | 0/5 |

| Task | Arm | Cost difference from control, mean (95% CI) | Verdict |
| --- | --- | --- | --- |
| single-file | gate-v1 | +$0.020 (−$0.007 to +$0.051) | inconclusive |
| single-file | gate-v2 | +$0.006 (−$0.008 to +$0.022) | inconclusive |
| cross-file | gate-v1 | +$0.005 (−$0.004 to +$0.013) | inconclusive |
| cross-file | gate-v2 | −$0.003 (−$0.010 to +$0.005) | inconclusive |
| edit | gate-v1 | +$0.001 (−$0.003 to +$0.007) | inconclusive |
| edit | gate-v2 | −$0.000 (−$0.008 to +$0.007) | inconclusive |

Per-session data is in `results/`, and the generated tables are in `results/summary.md`. To regrade, run `python3 analyze.py`.

## What Claude did

Tool calls, summed over the 5 runs in each cell. "Full" means a Read with no offset or limit.

| Task | Arm | Tool calls | Reads | Full reads | Read lengths (lines) |
| --- | --- | --- | --- | --- | --- |
| single-file | control | Grep 6, Read 5 | 5 | 0 | 40 to 250 |
| single-file | gate-v1 | Grep 9, Read 3, Bash 2 | 3 | 0 | 300 to 320 |
| single-file | gate-v2 | Grep 8, Read 5 | 5 | 0 | 20 to 350 |
| cross-file | all arms | Grep 11 to 13, Glob 4 to 5 | 0 | 0 | none |
| edit | all arms | Grep 5, Read 5, Edit 5 | 5 each | 0 | 5 to 12 |

The cross-file task, the one bulk-read is meant for, was answered with Grep alone in every run. The two Bash calls in gate-v1 were `sed` line ranges and a `grep`, and neither was over the limit.

## Where the tokens went

| Task | Arm | Cached tokens read per session | Cached tokens read per turn | Output tokens |
| --- | --- | --- | --- | --- |
| single-file | control | 138,826 | 43,383 | 1,216 |
| cross-file | control | 170,580 | 38,768 | 1,321 |
| edit | control | 190,547 | 47,637 | 923 |

Every turn re-sends everything already in context, which here was 39,000 to 48,000 tokens per turn in the control arm. Most of that is the system prompt, tool definitions, and skills, which were the same in every arm. The cross-file task pulled no file into context beyond Grep output and still read about 39,000 cached tokens per turn. On these tasks, how much Claude reads from files is a small part of the cost, and the number of turns is the larger part.

## Why this differs from the pilot

The pilot prompt ended "Read the file to find out", which asked for a full read. The hook blocked it, and Claude worked round it with grep and sed over 8 turns ($0.40, against $0.17 without the hook). The experiment's prompts ask the question without saying how to read the files, and with that wording Claude did not attempt a full read at all.

So the gate only comes into play when Claude decides, or is told, to read a large file whole. When that happens with the v1 message, the one pilot run shows it can cost more. The v2 message has not been tested in that situation.

## What this does and does not show

It shows that on these three tasks, with this model and this Claude Code version, Claude already avoids reading files of 367 to 1,227 lines in full. The gate therefore adds no measurable cost or saving.

It does not show what happens:

- on tasks that need a whole file understood, such as "summarise this module" or "review this file for bugs", where a full read is the natural move and where the gate is meant to help. All three tasks here could be answered by search, which favours Grep;
- on much larger files, or across a large codebase;
- with a smaller main model, other harnesses, or older Claude Code versions;
- in the conditions Spotify reported, a Java monorepo on their own harness.

## Next test

Two changes to the design, keeping everything else identical:

- Add a whole-file task, such as a summary graded against a checklist of facts from the file.
- Cross prompt wording as a second factor: neutral, or "read the file".

That tests the gate where it can act, and tests whether the v2 message gets Claude to delegate instead of working round the block.
