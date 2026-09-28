## Cost and behaviour by task and arm

| Task | Arm | n | Cost per task, mean (95% CI) | Claude | Worker | Turns | Quality | Blocked runs | Runs that delegated | Failed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| single-file | control | 5 | $0.119 ($0.110 to $0.126) | $0.119 | $0.0000 | 3.2 | 1.00 F1 | 0/5 | 0/5 | 0 |
| single-file | gate-v1 | 5 | $0.139 ($0.113 to $0.168) | $0.139 | $0.0000 | 3.8 | 1.00 F1 | 0/5 | 0/5 | 0 |
| single-file | gate-v2 | 5 | $0.125 ($0.114 to $0.139) | $0.125 | $0.0000 | 3.6 | 1.00 F1 | 0/5 | 0/5 | 0 |
| cross-file | control | 5 | $0.115 ($0.109 to $0.120) | $0.115 | $0.0000 | 4.4 | 1.00 F1 | 0/5 | 0/5 | 0 |
| cross-file | gate-v1 | 5 | $0.119 ($0.113 to $0.126) | $0.119 | $0.0000 | 4.6 | 1.00 F1 | 0/5 | 0/5 | 0 |
| cross-file | gate-v2 | 5 | $0.112 ($0.108 to $0.118) | $0.112 | $0.0000 | 4.0 | 1.00 F1 | 0/5 | 0/5 | 0 |
| edit | control | 5 | $0.108 ($0.103 to $0.113) | $0.108 | $0.0000 | 4.0 | 5/5 pass | 0/5 | 0/5 | 0 |
| edit | gate-v1 | 5 | $0.110 ($0.109 to $0.111) | $0.110 | $0.0000 | 4.0 | 5/5 pass | 0/5 | 0/5 | 0 |
| edit | gate-v2 | 5 | $0.108 ($0.103 to $0.113) | $0.108 | $0.0000 | 4.0 | 5/5 pass | 0/5 | 0/5 | 0 |

## Difference from control

| Task | Arm | Cost difference, mean (95% CI) | Ratio to control | Quality within margin | Verdict |
| --- | --- | --- | --- | --- | --- |
| single-file | gate-v1 | +0.020 (-0.007 to +0.051) | 1.17 | yes | inconclusive |
| single-file | gate-v2 | +0.006 (-0.008 to +0.022) | 1.05 | yes | inconclusive |
| cross-file | gate-v1 | +0.005 (-0.004 to +0.013) | 1.04 | yes | inconclusive |
| cross-file | gate-v2 | -0.003 (-0.010 to +0.005) | 0.98 | yes | inconclusive |
| edit | gate-v1 | +0.001 (-0.003 to +0.007) | 1.01 | yes | inconclusive |
| edit | gate-v2 | -0.000 (-0.008 to +0.007) | 1.00 | yes | inconclusive |

45 sessions, total cost $5.27.
