---
name: bulk-reader
description: Ask a cheaper model a question about large files instead of reading them into context. Use for files over 350 lines, questions that span three or more files, or summarising a large diff, and whenever a Read or cat was denied for file size.
---

<!-- Based on the bulk-reader skill in shunt from spotify/portal-ai-plugins (Apache-2.0), with changes. See NOTICE. -->

Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bulk-read" --question "<question>" --paths <file> [<file> ...]
```

The files go to the worker model and only its answer comes back to you.

- Ask one specific question per call. "Which functions write to the database, with line numbers" works better than "explain this file".
- Each call stands alone. For a follow-up, call again with the same `--paths`. Re-sending the files costs the worker tokens, not yours.
- To save a diff first, write it to a file (`git diff main > /tmp/diff.patch`) and pass that path.
- The answer cites line numbers. Before an edit, open the exact lines with `Read` and an `offset` and `limit`, and check them; do not edit from the summary alone.
- Do not use this for debugging that needs your own reasoning over the exact code. Read the relevant section with `offset` and `limit` instead.
