# LangSmith for Claude Code

A Claude Code plugin marketplace for building with LangSmith. It installs LangChain's tracing plugin and skills, adds the LangSmith and LangChain docs MCP servers, and adds langsmith-shunt, which keeps large files out of Claude's context and measures the tokens saved from LangSmith traces.

## Plugins

| Plugin | What it does | Source |
| --- | --- | --- |
| `langsmith-setup` | LangSmith MCP server (hosted, OAuth) and LangChain docs MCP server. `/langsmith-setup:setup` walks through keys and settings. `/langsmith-setup:doctor` checks tools, settings, plugins, and connectivity without changing anything. | This repo |
| `langsmith-shunt` | Hooks deny full reads of files over 350 lines. Claude asks a cheaper model about the file through the LangSmith LLM Gateway and gets back only the answer. Each delegation is a LangSmith run, and `/langsmith-shunt:savings` reports the tokens saved. [Details](plugins/langsmith-shunt/README.md) | This repo |
| `langsmith-tracing` | Traces Claude Code sessions, tool calls, subagents, and compaction to LangSmith | [langchain-ai/langsmith-claude-code-plugins](https://github.com/langchain-ai/langsmith-claude-code-plugins) |
| `langsmith-skills` | Skills for traces, datasets, evaluators, and custom apps in LangSmith | [langchain-ai/langsmith-skills](https://github.com/langchain-ai/langsmith-skills) |
| `langchain-skills` | Skills for building agents with LangChain, LangGraph, and Deep Agents | [langchain-ai/langchain-skills](https://github.com/langchain-ai/langchain-skills) |

The last three are LangChain's own plugins. This marketplace lists them so one `marketplace add` covers the whole setup, and installs them from their own repositories.

## Install

```bash
claude plugin marketplace add joel-langchain/langsmith-claude-code
```

```bash
claude plugin install langsmith-setup@langsmith-claude-code
```

```bash
claude plugin install langsmith-shunt@langsmith-claude-code
```

```bash
claude plugin install langsmith-tracing@langsmith-claude-code
```

```bash
claude plugin install langsmith-skills@langsmith-claude-code
```

```bash
claude plugin install langchain-skills@langsmith-claude-code
```

Then start a session and run `/langsmith-setup:setup`.

If `langsmith-tracing` is already installed from LangChain's own marketplace, skip it here. Two copies trace every session twice, and the doctor warns about it.

## Requirements

- Claude Code 2.1 or later
- `bash`, `curl`, and `jq` for langsmith-shunt, and `python3` for its savings report
- Node.js 18 or later for langsmith-tracing
- The [LangSmith CLI](https://github.com/langchain-ai/langsmith-cli) for langsmith-skills
- A LangSmith API key. For the default worker model, the key's workspace needs an Anthropic provider secret for the [LLM Gateway](https://docs.langchain.com/langsmith/llm-gateway). Without one, point langsmith-shunt at the Anthropic API directly (see its [configuration](plugins/langsmith-shunt/README.md#configuration)).

## Layout

```
.claude-plugin/marketplace.json   the marketplace: two local plugins, three from LangChain's repositories
plugins/langsmith-setup/          .mcp.json, setup and doctor skills, scripts/doctor
plugins/langsmith-shunt/          hooks/, scripts/, skills/, README.md
tests/                            hook, transport, and report tests (no network, no keys)
```

## Development

```bash
bash tests/run.sh
```

```bash
claude plugin validate .
```

```bash
claude --plugin-dir plugins/langsmith-shunt
```

The tests run the hooks on generated files, run the scripts against a stub `curl`, and run the savings report against a local stub of the LangSmith API.

## Credits

langsmith-shunt follows the design of Spotify's [shunt](https://github.com/spotify/portal-ai-plugins/tree/main/plugins/shunt) (Apache-2.0). See [NOTICE](NOTICE). The single-repository layout follows [ECC](https://github.com/affaan-m/ECC).

Apache License 2.0. See [LICENSE](LICENSE).
