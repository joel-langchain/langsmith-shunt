#!/bin/bash
# Tests for bulk-read and code-write against a stub curl, so no request leaves
# the machine. The stub records every request and answers the model endpoint
# and the LangSmith runs endpoint with canned responses.

# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/curl" <<'STUB'
#!/bin/bash
n=$(($(cat "$STUB_DIR/count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$STUB_DIR/count"
printf '%s\n' "$@" >"$STUB_DIR/argv.$n"
out="" data="" headers="" url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -H) headers="${2#@}"; shift 2 ;;
    --data-binary) data="${2#@}"; shift 2 ;;
    -w | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "$url" >"$STUB_DIR/url.$n"
[ -f "$data" ] && cp "$data" "$STUB_DIR/body.$n"
[ -f "$headers" ] && cp "$headers" "$STUB_DIR/headers.$n"
case "$url" in
  */runs) status="${STUB_RUNS_STATUS:-202}" response='{}' ;;
  *) status="${STUB_MODEL_STATUS:-200}" response=$(cat "$STUB_MODEL_RESPONSE") ;;
esac
[ -n "$out" ] && [ "$out" != /dev/null ] && printf '%s' "$response" >"$out"
printf '%s' "$status"
STUB
chmod +x "$STUB_BIN/curl"

seq 1 600 | sed 's/^/export const value = /' >"$WORK/big.ts"
printf 'describe("order", () => {\n  it("works", () => {});\n});\n' >"$WORK/ref.test.ts"

ANTHROPIC_OK="$WORK/anthropic-ok.json"
echo '{"content":[{"type":"text","text":"- value: exported 600 times"}],"usage":{"input_tokens":4321,"output_tokens":12},"stop_reason":"end_turn"}' >"$ANTHROPIC_OK"
ANTHROPIC_FENCED="$WORK/anthropic-fenced.json"
jq -n '{content: [{type: "text", text: "```ts\ndescribe(\"user\", () => {\n  const s = \"```\";\n});\n```"}], usage: {input_tokens: 90, output_tokens: 30}, stop_reason: "end_turn"}' >"$ANTHROPIC_FENCED"
ANTHROPIC_CUT="$WORK/anthropic-cut.json"
echo '{"content":[{"type":"text","text":"- partial"}],"usage":{"input_tokens":10,"output_tokens":8192},"stop_reason":"max_tokens"}' >"$ANTHROPIC_CUT"
OPENAI_OK="$WORK/openai-ok.json"
echo '{"choices":[{"message":{"content":"- from openai"},"finish_reason":"stop"}],"usage":{"prompt_tokens":777,"completion_tokens":7}}' >"$OPENAI_OK"
ERROR_403_TEXT="$WORK/error-403.txt"
printf 'missing permission gateway:invoke' >"$ERROR_403_TEXT"
ERROR_401="$WORK/error.json"
echo '{"error":{"type":"authentication_error","message":"invalid x-api-key"}}' >"$ERROR_401"

# run <script> <response file> [VAR=value ...] -- <args...>
# Leaves stdout in $WORK/out, stderr in $WORK/err, exit code in $rc.
run() {
  local script="$1" response="$2"
  shift 2
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    envs+=("$1")
    shift
  done
  shift
  export STUB_DIR="$WORK/calls"
  rm -rf "$STUB_DIR"
  mkdir -p "$STUB_DIR"
  env -i HOME="$HOME" PATH="$STUB_BIN:/usr/bin:/bin" \
    STUB_DIR="$STUB_DIR" STUB_MODEL_RESPONSE="$response" \
    SHUNT_API_KEY=test-worker-key SHUNT_LANGSMITH_API_KEY=test-trace-key \
    CLAUDE_CODE_SESSION_ID=session-123 \
    ${envs[@]+"${envs[@]}"} \
    "$SHUNT/scripts/$script" "$@" >"$WORK/out" 2>"$WORK/err"
  rc=$?
}

calls() { cat "$WORK/calls/count" 2>/dev/null || echo 0; }
body() { cat "$WORK/calls/body.$1"; }

echo "bulk-read, Anthropic through the gateway"
run bulk-read "$ANTHROPIC_OK" -- --question "What is exported?" --paths "$WORK/big.ts"
assert "exits 0" [ "$rc" -eq 0 ]
assert "prints the answer" contains "$WORK/out" "- value: exported 600 times"
assert "reports tokens on stderr" contains "$WORK/err" "read 4321 tokens and returned 12"
assert "makes two requests (model, then run)" [ "$(calls)" -eq 2 ]
assert "calls the gateway messages endpoint" [ "$(cat "$WORK/calls/url.1")" = "https://gateway.smith.langchain.com/anthropic/v1/messages" ]
assert "sends the worker key in a header file" contains "$WORK/calls/headers.1" "x-api-key: test-worker-key"
assert "keeps the worker key out of argv" not_contains "$WORK/calls/argv.1" "test-worker-key"
assert "uses Haiku by default" [ "$(body 1 | jq -r .model)" = "claude-haiku-4-5-20251001" ]
assert "wraps the file in tags" [ "$(body 1 | jq -r '.messages[0].content' | grep -c '<file path=')" -eq 1 ]
assert "numbers the lines" [ "$(body 1 | jq -r '.messages[0].content' | grep -c $'^   600\t')" -eq 1 ]
assert "sends temperature 0.2" [ "$(body 1 | jq -r .temperature)" = "0.2" ]
assert "records the run at LANGSMITH_ENDPOINT/runs" [ "$(cat "$WORK/calls/url.2")" = "https://api.smith.langchain.com/runs" ]
assert "sends the trace key" contains "$WORK/calls/headers.2" "x-api-key: test-trace-key"
assert "run is named shunt:bulk-read" [ "$(body 2 | jq -r .name)" = "shunt:bulk-read" ]
assert "run carries input tokens" [ "$(body 2 | jq -r .outputs.usage_metadata.input_tokens)" = 4321 ]
assert "run carries output tokens" [ "$(body 2 | jq -r .outputs.usage_metadata.output_tokens)" = 12 ]
assert "run thread_id is the Claude session" [ "$(body 2 | jq -r .extra.metadata.thread_id)" = session-123 ]
assert "run has the langsmith-shunt tag" [ "$(body 2 | jq -r '.tags[0]')" = langsmith-shunt ]
assert "run has ls_model_name for cost" [ "$(body 2 | jq -r .extra.metadata.ls_model_name)" = claude-haiku-4-5-20251001 ]
assert "run records file lines, not contents" [ "$(body 2 | jq -r .inputs.file_lines)" = 600 ]
assert "run does not upload the file" [ "$(body 2 | grep -c 'export const value')" -eq 0 ]
assert "dotted_order ends with the run id" [ "$(body 2 | jq -r '.id as $i | .dotted_order | endswith($i)')" = true ]
assert "dotted_order has the timestamp format" [ "$(body 2 | jq -r '.dotted_order[0:22] | test("^[0-9]{8}T[0-9]{12}Z$")')" = true ]
assert "project defaults to claude-code" [ "$(body 2 | jq -r .session_name)" = claude-code ]
assert "prints the run id" contains "$WORK/err" "LangSmith run "

echo
echo "bulk-read, configuration"
run bulk-read "$ANTHROPIC_OK" CC_LANGSMITH_PROJECT=my-project LANGSMITH_ENDPOINT=https://eu.api.smith.langchain.com -- --question q --paths "$WORK/big.ts"
assert "EU endpoint picks the EU gateway" [ "$(cat "$WORK/calls/url.1")" = "https://eu.gateway.smith.langchain.com/anthropic/v1/messages" ]
assert "run goes to the EU API" [ "$(cat "$WORK/calls/url.2")" = "https://eu.api.smith.langchain.com/runs" ]
assert "project follows CC_LANGSMITH_PROJECT" [ "$(body 2 | jq -r .session_name)" = my-project ]

run bulk-read "$ANTHROPIC_OK" SHUNT_TEMPERATURE= -- --question q --paths "$WORK/big.ts"
assert "empty SHUNT_TEMPERATURE omits temperature" [ "$(body 1 | jq 'has("temperature")')" = false ]

run bulk-read "$ANTHROPIC_OK" SHUNT_TRACE=false -- --question q --paths "$WORK/big.ts"
assert "SHUNT_TRACE=false skips the run" [ "$(calls)" -eq 1 ]

run bulk-read "$ANTHROPIC_OK" STUB_RUNS_STATUS=500 -- --question q --paths "$WORK/big.ts"
assert "failed run upload still exits 0" [ "$rc" -eq 0 ]
assert "failed run upload still prints the answer" contains "$WORK/out" "exported 600 times"
assert "failed run upload warns" contains "$WORK/err" "could not record the LangSmith run"

run bulk-read "$OPENAI_OK" SHUNT_PROVIDER=openai SHUNT_MODEL=gpt-test -- --question q --paths "$WORK/big.ts"
assert "OpenAI: calls chat completions" [ "$(cat "$WORK/calls/url.1")" = "https://gateway.smith.langchain.com/openai/v1/chat/completions" ]
assert "OpenAI: bearer auth" contains "$WORK/calls/headers.1" "authorization: Bearer test-worker-key"
assert "OpenAI: prints the answer" contains "$WORK/out" "- from openai"
assert "OpenAI: run carries prompt tokens" [ "$(body 2 | jq -r .outputs.usage_metadata.input_tokens)" = 777 ]

run bulk-read "$OPENAI_OK" SHUNT_PROVIDER=openai -- --question q --paths "$WORK/big.ts"
assert "OpenAI without SHUNT_MODEL fails" [ "$rc" -ne 0 ]
assert "OpenAI without SHUNT_MODEL makes no request" [ "$(calls)" -eq 0 ]

run bulk-read "$ANTHROPIC_OK" SHUNT_BASE_URL=https://api.anthropic.com -- --question q --paths "$WORK/big.ts"
assert "SHUNT_BASE_URL replaces the gateway" [ "$(cat "$WORK/calls/url.1")" = "https://api.anthropic.com/v1/messages" ]

echo
echo "bulk-read, errors"
run bulk-read "$ERROR_401" STUB_MODEL_STATUS=401 -- --question q --paths "$WORK/big.ts"
assert "HTTP 401 exits non-zero" [ "$rc" -ne 0 ]
assert "HTTP 401 shows the provider message" contains "$WORK/err" "HTTP 401: invalid x-api-key"
assert "HTTP 401 records no run" [ "$(calls)" -eq 1 ]

run bulk-read "$ERROR_403_TEXT" STUB_MODEL_STATUS=403 -- --question q --paths "$WORK/big.ts"
assert "plain-text error body is shown" contains "$WORK/err" "HTTP 403: missing permission gateway:invoke"
assert "missing gateway permission gets a fix" contains "$WORK/err" "no permission to call the LLM Gateway"

run bulk-read "$ANTHROPIC_CUT" -- --question q --paths "$WORK/big.ts"
assert "max_tokens stop warns" contains "$WORK/err" "cut off"

run bulk-read "$ANTHROPIC_OK" -- --question q --paths "$WORK/missing.ts"
assert "missing file exits non-zero" [ "$rc" -ne 0 ]
assert "missing file makes no request" [ "$(calls)" -eq 0 ]

run bulk-read "$ANTHROPIC_OK" -- --question
assert "missing arguments exit non-zero" [ "$rc" -ne 0 ]

run bulk-read "$ANTHROPIC_OK" SHUNT_MAX_INPUT_BYTES=100 -- --question q --paths "$WORK/big.ts"
assert "oversized request is refused" contains "$WORK/err" "over SHUNT_MAX_INPUT_BYTES"
assert "oversized request makes no call" [ "$(calls)" -eq 0 ]

run bulk-read "$ANTHROPIC_OK" SHUNT_API_KEY= LANGSMITH_API_KEY= CC_LANGSMITH_API_KEY= -- --question q --paths "$WORK/big.ts"
assert "no worker key exits non-zero" [ "$rc" -ne 0 ]

echo
echo "code-write"
target="$WORK/gen/user.test.ts"
run code-write "$ANTHROPIC_FENCED" -- --spec "tests for user" --reference "$WORK/ref.test.ts" --target "$target"
assert "exits 0" [ "$rc" -eq 0 ]
assert "writes the target" [ -f "$target" ]
assert "strips the outer fence" [ "$(head -1 "$target")" = 'describe("user", () => {' ]
assert "keeps fences inside the code" contains "$target" 'const s = "```";'
assert "reports the line count only" [ "$(cat "$WORK/out")" = "Wrote 3 lines to $target" ]
assert "run is named shunt:code-write" [ "$(body 2 | jq -r .name)" = "shunt:code-write" ]
assert "run records lines written" [ "$(body 2 | jq -r .outputs.lines_written)" = 3 ]

run code-write "$ANTHROPIC_FENCED" -- --spec "tests for user" --reference "$WORK/ref.test.ts" --target "$target"
assert "refuses to overwrite" [ "$rc" -ne 0 ]
assert "refusal makes no request" [ "$(calls)" -eq 0 ]

run code-write "$ANTHROPIC_FENCED" -- --spec "tests for user" --reference "$WORK/ref.test.ts" --target "$target" --overwrite
assert "--overwrite replaces the target" [ "$rc" -eq 0 ]

run code-write "$ANTHROPIC_FENCED" -- --spec "tests for user"
assert "no reference exits non-zero" [ "$rc" -ne 0 ]

run code-write "$ANTHROPIC_FENCED" -- --spec "stub" --reference "$WORK/ref.test.ts"
assert "without --target prints the code" contains "$WORK/out" 'describe("user", () => {'

summary
