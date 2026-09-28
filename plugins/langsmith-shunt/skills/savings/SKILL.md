---
name: savings
description: Report the tokens langsmith-shunt delegations saved, measured from LangSmith runs.
disable-model-invocation: true
argument-hint: "[--days 7] [--current | --session <id>] [--project <name>]"
---

Run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/savings-report" $ARGUMENTS
```

Show the output as it is, including the numbered notes that explain each figure. If it reports no Claude calls, explain that the estimate needs the langsmith-tracing plugin writing to the same LangSmith project.

`--current` limits the report to this Claude Code session.
