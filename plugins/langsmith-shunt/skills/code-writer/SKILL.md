---
name: code-writer
description: Have a cheaper model write a file that follows an existing one, such as tests in the style of an existing test file, fixtures, config stubs, or handlers that repeat a pattern. Use when the new file is mostly pattern-following rather than new logic.
---

<!-- Based on the code-writer skill in shunt from spotify/portal-ai-plugins (Apache-2.0), with changes. See NOTICE. -->

Run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/code-write" --spec "<what to write>" --reference <file> [--reference <file> ...] --target <new file>
```

- `--reference` is required. Pass the file whose structure the output should copy, plus the source file it covers if there is one.
- With `--target` the file is written to disk and you see only the line count. Leave `--target` out to get the code on stdout instead.
- An existing `--target` is not replaced unless you add `--overwrite`.
- For a follow-up, pass the file the last call wrote as a `--reference`.
- Check the result the same way you would check your own code: run the tests or the linter on the target file. Read only the parts that fail.
- Write logic that needs reasoning yourself.
