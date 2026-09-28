---
name: doctor
description: Check the LangSmith Claude Code setup (tools, environment variables, enabled plugins, and whether LangSmith and the worker model answer). Use when tracing, the LangSmith MCP server, or langsmith-shunt delegation is not working.
argument-hint: "[--offline] [--live]"
---

Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doctor" $ARGUMENTS
```

The script only reads. It prints `ok`, `warn`, or `fail` per check and never prints a key.

For each `warn` or `fail`, give the fix in one line. Do not change any settings file unless the user asks. `--live` sends one request with `max_tokens` 1 to the worker model, so run it only when the user asks or agrees.

MCP servers are not checked by the script. If the user reports a problem with them, ask them to run `/mcp` and check that `plugin:langsmith-setup:langsmith` is connected and authenticated.
