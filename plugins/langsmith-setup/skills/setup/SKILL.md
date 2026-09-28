---
name: setup
description: Walk the user through connecting Claude Code to LangSmith, covering tracing, the LLM Gateway worker for langsmith-shunt, the MCP servers, and the LangSmith CLI.
disable-model-invocation: true
---

Set up LangSmith for Claude Code one step at a time. Confirm each step with the user before moving on.

Never ask the user to paste an API key into the conversation, and never print one. Write every setting except the key yourself, and leave the key as a placeholder for the user to fill in.

## 1. Check the current state

Run `"${CLAUDE_PLUGIN_ROOT}/scripts/doctor" --offline` and summarise what is already in place.

## 2. Choose where settings live

Ask which of these to use:

- `~/.claude/settings.json` applies to every project on this machine.
- `.claude/settings.local.json` applies to this project only. Claude Code keeps it out of git. Check that `.gitignore` covers it.

Never put a key in `.claude/settings.json` inside a repository, because that file is usually committed.

## 3. Tracing

Merge this into the `env` block of the chosen file, keeping any keys already there:

```json
{
  "env": {
    "TRACE_TO_LANGSMITH": "true",
    "CC_LANGSMITH_API_KEY": "<LangSmith API key>",
    "CC_LANGSMITH_PROJECT": "claude-code"
  }
}
```

Ask for the project name. For an EU LangSmith account, also set `"LANGSMITH_ENDPOINT": "https://eu.api.smith.langchain.com"` and `"LANGSMITH_MCP_URL": "https://eu.api.smith.langchain.com/mcp"`. For self-hosted LangSmith, set `LANGSMITH_ENDPOINT` to the instance's API URL.

Tell the user to replace the placeholder with a key from LangSmith, under Settings, then API Keys.

## 4. Worker model for langsmith-shunt

By default langsmith-shunt calls Claude Haiku through the LangSmith LLM Gateway with the same LangSmith key. That works when the key's workspace has an Anthropic provider secret configured for the gateway (https://docs.langchain.com/langsmith/llm-gateway). Ask the user which case applies:

- **Gateway, same key.** Nothing to add.
- **Gateway, different workspace.** Add `"SHUNT_API_KEY": "<LangSmith key for that workspace>"`.
- **OpenAI through the gateway.** Add `"SHUNT_PROVIDER": "openai"` and `"SHUNT_MODEL": "<model name>"`.
- **No gateway.** Add `"SHUNT_BASE_URL": "https://api.anthropic.com"` and `"SHUNT_API_KEY": "<Anthropic API key>"`. Delegations are still recorded as LangSmith runs.

`SHUNT_MIN_LINES` (default 350) sets the file length at which full reads are redirected.

## 5. MCP servers

This plugin adds two MCP servers: `langsmith` (the hosted LangSmith MCP server, which signs in with OAuth) and `langchain-docs`. Ask the user to run `/mcp`, choose `plugin:langsmith-setup:langsmith`, and complete the sign-in.

## 6. LangSmith CLI

The langsmith-skills plugin uses the `langsmith` CLI. If the doctor reported it missing, show the install command and run it only if the user agrees:

```bash
curl -sSL https://raw.githubusercontent.com/langchain-ai/langsmith-cli/main/scripts/install.sh | sh
```

## 7. Finish

Settings in `env` take effect in a new session. Ask the user to restart Claude Code, then run `/langsmith-setup:doctor --live` to check the keys and the worker model.
