# langsmith-shunt

A Claude Code plugin that keeps large files out of Claude's context. A hook denies a full read of any file over 350 lines, and Claude asks a question about the file through a script instead. The script sends the file to a cheaper worker model (Claude Haiku 4.5 through the LangSmith LLM Gateway by default) and returns only the answer. Each delegation is recorded as a LangSmith run, so the tokens saved can be measured from traces.

The design follows Spotify's [shunt](https://github.com/spotify/portal-ai-plugins/tree/main/plugins/shunt), with the worker reached through the LangSmith LLM Gateway instead of the Spotify Portal CLI, and with every delegation traced.

## Install

```bash
claude plugin marketplace add joel-langchain/langsmith-shunt
```

```bash
claude plugin install langsmith-shunt@langsmith-shunt
```

If Claude Code already runs through the LangSmith LLM Gateway (`ANTHROPIC_BASE_URL` is the gateway), the worker uses the same address and key, and there is nothing to set.

Otherwise, add a key to the `env` block of `~/.claude/settings.json`, or of `.claude/settings.local.json` for one project:

```json
{
  "env": {
    "SHUNT_API_KEY": "<LangSmith API key with gateway access>"
  }
}
```

The key needs permission to call the gateway, and its workspace needs an Anthropic provider secret. A tracing-only key usually has neither, so the plugin never uses `CC_LANGSMITH_API_KEY` for the worker. The LLM Gateway is not on the free Developer plan. Without it, call the Anthropic API directly:

```json
{
  "env": {
    "SHUNT_BASE_URL": "https://api.anthropic.com",
    "SHUNT_API_KEY": "<Anthropic API key>",
    "SHUNT_LANGSMITH_API_KEY": "<LangSmith API key>"
  }
}
```

If you already use LangChain's [langsmith-tracing](https://github.com/langchain-ai/langsmith-claude-code-plugins) plugin, langsmith-shunt records its runs with the same `CC_LANGSMITH_API_KEY` into the same `CC_LANGSMITH_PROJECT`, and the savings report can compare delegations with the rest of the session. The report needs to read runs, which a tracing key may not allow; set `SHUNT_LANGSMITH_API_KEY` to a key with read access if it says so.

## How it works

```
Claude ── Read big.ts ──► PreToolUse hook ── over 350 lines? ── no ──► Read runs
                                │
                               yes: deny, and name the bulk-reader skill
                                │
Claude ── bulk-read --question "..." --paths big.ts
                                │
                                ├──► worker model via LLM Gateway ──► answer printed for Claude
                                │
                                └──► LangSmith run: token counts, file size, thread_id = session
```

There are three layers, from hard to soft. Paths are under `plugins/langsmith-shunt/`.

| Layer | Files | Role |
| --- | --- | --- |
| Hooks | `hooks/check-file-size`, `hooks/check-bash-read` | Deny full reads of large files through `Read`, `cat`, `less`, `more`, `head`, and `tail`. Run before the tool, so Claude cannot ignore them. |
| Scripts | `scripts/bulk-read`, `scripts/code-write` | Call the worker model, clean the output, and record the LangSmith run. Claude calls them with named arguments. |
| Skills | `skills/bulk-reader`, `skills/code-writer`, `skills/savings` | Tell Claude when and how to call the scripts. `/langsmith-shunt:savings` runs the report. |

What passes the hooks unchanged: reads with `offset` or `limit`, files at or under the limit, binary files, notebooks, missing files, commands with pipes, redirects, or substitutions, and `head` or `tail` calls that print at most the limit.

`code-write` writes a new file from a spec and at least one reference file. With `--target` the file goes to disk and Claude sees only the line count.

## Measuring the savings

Each run records the worker's token counts from the API response and the Claude Code session id as `thread_id`. The langsmith-tracing plugin writes the same `thread_id` on every Claude call, so with both plugins writing to one project, `/langsmith-shunt:savings` joins them.

| Figure | Formula |
| --- | --- |
| Context tokens avoided | Sum over bulk-reads of (worker input tokens minus worker output tokens) |
| Input tokens avoided, estimate | Each bulk-read's avoided tokens times the number of main-agent Claude calls later in the same session, summed |
| Input reduction, estimate | Input tokens avoided / (Claude input tokens, subagents included, + input tokens avoided) |
| Code tokens written by worker | Sum over code-writes of worker output tokens |

Limits of these figures:

- The worker input also holds the instructions and the question, so the avoided figure is slightly high.
- The estimate assumes a file read in full would have stayed in context for every later call. Compaction would shorten that. Prompt caching bills re-read tokens at a lower rate than new ones, so the token figure is not a cost figure.
- Token counts come from the worker's tokenizer. They match Claude's counts only when the worker is a Claude model.
- The report does not measure answer quality. Whether Claude needed a follow-up Read after an answer shows up in the session trace.

```bash
python3 plugins/langsmith-shunt/scripts/savings-report --days 7
```

```bash
python3 plugins/langsmith-shunt/scripts/savings-report --current --json
```

## Configuration

Set these in the same `env` block.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SHUNT_MIN_LINES` | `350` | Line count above which a full read is denied |
| `SHUNT_DISABLED` | unset | `1` or `true` turns the hooks off |
| `SHUNT_PROVIDER` | `anthropic` | `anthropic` or `openai` API format |
| `SHUNT_MODEL` | `claude-haiku-4-5-20251001` | Worker model. Required for `openai` |
| `SHUNT_BASE_URL` | Claude Code's `ANTHROPIC_BASE_URL` when it is the gateway, else the LLM Gateway for the provider | For example `https://api.anthropic.com` to skip the gateway |
| `SHUNT_API_KEY` | Claude Code's own gateway key when `ANTHROPIC_BASE_URL` is the LangSmith Gateway, then `LANGSMITH_API_KEY` | Worker key. Through the gateway this is a LangSmith key with gateway access whose workspace has the provider secret |
| `SHUNT_LANGSMITH_API_KEY` | `CC_LANGSMITH_API_KEY`, then `LANGSMITH_API_KEY` | Key for recording runs |
| `SHUNT_LANGSMITH_PROJECT` | `CC_LANGSMITH_PROJECT`, then `LANGSMITH_PROJECT`, then `claude-code` | Project for the runs |
| `SHUNT_TRACE` | `true` | `false` stops recording runs |
| `LANGSMITH_ENDPOINT` | `https://api.smith.langchain.com` | An EU endpoint also switches the gateway to `eu.gateway.smith.langchain.com` |
| `SHUNT_TEMPERATURE` | `0.2` | Set to an empty string to leave it out, for models that reject it |
| `SHUNT_MAX_TOKENS` | `8192` | Longest answer |
| `SHUNT_MAX_INPUT_BYTES` | `600000` | Largest request |
| `SHUNT_TIMEOUT_SECONDS` | `180` | Worker request timeout |

Requires Claude Code 2.1 or later, `bash`, `curl`, and `jq`. The savings report requires `python3` (standard library only).

## Privacy

The worker receives the full files. The LangSmith run records the question, the file paths, line and byte counts, and the answer, not the file contents. The LLM Gateway keeps its own trace of each worker call in the key's workspace, following that workspace's settings.

## Changes from Spotify's shunt

- The worker is called over HTTP through the LangSmith LLM Gateway, or any Anthropic or OpenAI compatible endpoint, instead of the Portal CLI. The request body goes in a file rather than on the command line, and keys go in a header file so they stay out of the process list.
- Each delegation is recorded as a LangSmith run with token counts from the API response, where Spotify's benchmarks estimate tokens as characters divided by 4.
- The hooks use the current `permissionDecision` output format and emit only a deny.
- `head` and `tail` are counted by the lines they print, several files in one `cat` are summed, and a `cd` earlier in the command is followed.
- Binary files and notebooks are skipped.
- `bulk-read` numbers each line, the way Claude's Read tool does, so answers can cite lines.
- `code-write` accepts several references and does not overwrite an existing target without `--overwrite`. Only a fence around the whole answer is removed.

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

The tests run the hooks on generated files, run the scripts against a stub `curl`, and run the savings report against a local stub of the LangSmith API. None of them need network access or keys.

## Credits

Based on the design of Spotify's [shunt](https://github.com/spotify/portal-ai-plugins/tree/main/plugins/shunt) (Apache-2.0). See [NOTICE](NOTICE).

Apache License 2.0. See [LICENSE](LICENSE).
