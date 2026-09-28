## Cost and behaviour by cell

| Task and wording | Arm | n | Cost per task, mean (95% CI) | Claude | Worker | Turns | Fact coverage | Runs with a full read | Runs blocked | Runs that delegated | Failed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| one-file-neutral | control | 5 | $0.212 ($0.211 to $0.212) | $0.212 | $0.0000 | 2.0 | 1.00 | 5/5 | 0/5 | 0/5 | 0 |
| one-file-neutral | gate-v1 | 5 | $0.184 ($0.173 to $0.192) | $0.156 | $0.0278 | 5.6 | 0.95 | 0/5 | 0/5 | 5/5 | 0 |
| one-file-neutral | gate-v2 | 5 | $0.181 ($0.167 to $0.202) | $0.153 | $0.0280 | 5.4 | 1.00 | 0/5 | 0/5 | 5/5 | 0 |
| one-file-read | control | 5 | $0.210 ($0.209 to $0.211) | $0.210 | $0.0000 | 2.0 | 1.00 | 5/5 | 0/5 | 0/5 | 0 |
| one-file-read | gate-v1 | 5 | $0.168 ($0.166 to $0.170) | $0.144 | $0.0235 | 5.0 | 1.00 | 1/5 | 1/5 | 5/5 | 0 |
| one-file-read | gate-v2 | 5 | $0.167 ($0.166 to $0.169) | $0.142 | $0.0248 | 4.2 | 1.00 | 2/5 | 2/5 | 5/5 | 0 |
| four-file-neutral | control | 5 | $0.368 ($0.363 to $0.374) | $0.368 | $0.0000 | 6.0 | 0.96 | 5/5 | 0/5 | 0/5 | 0 |
| four-file-neutral | gate-v1 | 5 | $0.296 ($0.254 to $0.369) | $0.243 | $0.0535 | 6.2 | 0.92 | 0/5 | 0/5 | 5/5 | 0 |
| four-file-neutral | gate-v2 | 5 | $0.251 ($0.243 to $0.260) | $0.201 | $0.0500 | 6.6 | 0.84 | 0/5 | 0/5 | 5/5 | 0 |
| four-file-read | control | 5 | $0.392 ($0.350 to $0.475) | $0.392 | $0.0000 | 5.0 | 1.00 | 5/5 | 0/5 | 0/5 | 0 |
| four-file-read | gate-v1 | 5 | $0.285 ($0.219 to $0.382) | $0.230 | $0.0552 | 5.8 | 0.92 | 1/5 | 1/5 | 5/5 | 0 |
| four-file-read | gate-v2 | 5 | $0.322 ($0.273 to $0.378) | $0.261 | $0.0617 | 6.8 | 0.90 | 3/5 | 3/5 | 5/5 | 0 |

## Difference from control

| Task and wording | Arm | Cost difference, mean (95% CI) | Ratio to control | Coverage within margin | Verdict |
| --- | --- | --- | --- | --- | --- |
| one-file-neutral | gate-v1 | -0.028 (-0.038 to -0.020) | 0.87 | yes | saves |
| one-file-neutral | gate-v2 | -0.031 (-0.045 to -0.010) | 0.86 | yes | saves |
| one-file-read | gate-v1 | -0.042 (-0.044 to -0.040) | 0.80 | yes | saves |
| one-file-read | gate-v2 | -0.043 (-0.045 to -0.041) | 0.80 | yes | saves |
| four-file-neutral | gate-v1 | -0.072 (-0.115 to +0.002) | 0.81 | yes | inconclusive |
| four-file-neutral | gate-v2 | -0.117 (-0.126 to -0.107) | 0.68 | no | inconclusive |
| four-file-read | gate-v1 | -0.107 (-0.217 to +0.002) | 0.73 | yes | inconclusive |
| four-file-read | gate-v2 | -0.070 (-0.166 to +0.013) | 0.82 | yes | inconclusive |

60 sessions, total cost $15.18.
