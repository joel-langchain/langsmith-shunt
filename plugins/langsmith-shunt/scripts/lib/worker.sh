# Shared plumbing for bulk-read and code-write.
#
# Each delegation is one request to a cheaper worker model, by default Claude
# Haiku through the LangSmith LLM Gateway, followed by one LangSmith run that
# records the token counts. The run carries the Claude Code session id as
# thread_id, the same key the langsmith-tracing plugin uses, so a delegation
# sits in the same LangSmith thread as the session that asked for it.
#
# Every call stands alone. Nothing is kept between calls, and a follow-up
# question re-sends the files, which costs the worker tokens but not Claude's.

SHUNT_VERSION="0.1.0"

LANGSMITH_ENDPOINT="${LANGSMITH_ENDPOINT:-https://api.smith.langchain.com}"
LANGSMITH_ENDPOINT="${LANGSMITH_ENDPOINT%/}"

case "$LANGSMITH_ENDPOINT" in
  *eu.api.smith.langchain.com*) shunt_gateway="https://eu.gateway.smith.langchain.com" ;;
  *) shunt_gateway="https://gateway.smith.langchain.com" ;;
esac

SHUNT_PROVIDER="${SHUNT_PROVIDER:-anthropic}"
case "$SHUNT_PROVIDER" in
  anthropic)
    SHUNT_BASE_URL="${SHUNT_BASE_URL:-$shunt_gateway/anthropic}"
    SHUNT_MODEL="${SHUNT_MODEL:-claude-haiku-4-5-20251001}"
    ;;
  openai)
    SHUNT_BASE_URL="${SHUNT_BASE_URL:-$shunt_gateway/openai/v1}"
    SHUNT_MODEL="${SHUNT_MODEL:-}"
    ;;
  *)
    echo "Error: SHUNT_PROVIDER must be anthropic or openai, not '$SHUNT_PROVIDER'." >&2
    exit 1
    ;;
esac
SHUNT_BASE_URL="${SHUNT_BASE_URL%/}"

# Key for the worker model. Through the gateway this is a LangSmith API key
# whose workspace has the provider secret configured.
SHUNT_API_KEY="${SHUNT_API_KEY:-${LANGSMITH_API_KEY:-${CC_LANGSMITH_API_KEY:-}}}"

# Key and project for the delegation runs. Defaults match the
# langsmith-tracing plugin so both land in one project.
SHUNT_LANGSMITH_API_KEY="${SHUNT_LANGSMITH_API_KEY:-${CC_LANGSMITH_API_KEY:-${LANGSMITH_API_KEY:-}}}"
SHUNT_LANGSMITH_PROJECT="${SHUNT_LANGSMITH_PROJECT:-${CC_LANGSMITH_PROJECT:-${LANGSMITH_PROJECT:-claude-code}}}"
SHUNT_TRACE="${SHUNT_TRACE:-true}"

SHUNT_TEMPERATURE="${SHUNT_TEMPERATURE-0.2}"
SHUNT_MAX_TOKENS="${SHUNT_MAX_TOKENS:-8192}"
SHUNT_TIMEOUT_SECONDS="${SHUNT_TIMEOUT_SECONDS:-180}"
SHUNT_MAX_INPUT_BYTES="${SHUNT_MAX_INPUT_BYTES:-600000}"

SHUNT_TMPFILES=()
trap 'rm -f "${SHUNT_TMPFILES[@]}"' EXIT

# mktemp with cleanup on exit. Usage: shunt_tmpfile <varname>
shunt_tmpfile() {
  local f
  f=$(mktemp) || return 1
  chmod 600 "$f"
  SHUNT_TMPFILES+=("$f")
  printf -v "$1" '%s' "$f"
}

shunt_preflight() {
  local missing=""
  command -v jq >/dev/null 2>&1 || missing="$missing jq"
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  if [ -n "$missing" ]; then
    echo "Error: missing required command(s):$missing" >&2
    return 1
  fi
  if [ -z "$SHUNT_API_KEY" ]; then
    echo "Error: no key for the worker model. Set SHUNT_API_KEY, or LANGSMITH_API_KEY to use the LangSmith LLM Gateway." >&2
    return 1
  fi
  if [ -z "$SHUNT_MODEL" ]; then
    echo "Error: SHUNT_MODEL is required when SHUNT_PROVIDER=openai." >&2
    return 1
  fi
}

shunt_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}

shunt_now() {
  date -u +%Y-%m-%dT%H:%M:%S.000000Z
}

# Writes a curl header file so keys stay out of the process list.
#   $1 output file  $2... header lines
shunt_headers() {
  local out="$1"
  shift
  printf '%s\n' "$@" >"$out"
}

# Sends one request to the worker model.
#   $1 file with the system prompt  $2 file with the user message
# Sets SHUNT_TEXT_FILE, SHUNT_INPUT_TOKENS, SHUNT_OUTPUT_TOKENS, SHUNT_STOP.
shunt_call() {
  local system_file="$1" message_file="$2"
  local payload headers response url status bytes err

  bytes=$(wc -c <"$message_file" | tr -d ' ')
  if [ "$bytes" -gt "$SHUNT_MAX_INPUT_BYTES" ]; then
    echo "Error: request is $bytes bytes, over SHUNT_MAX_INPUT_BYTES ($SHUNT_MAX_INPUT_BYTES). Send fewer or smaller files." >&2
    return 1
  fi

  shunt_tmpfile payload || return 1
  shunt_tmpfile headers || return 1
  shunt_tmpfile response || return 1
  shunt_tmpfile SHUNT_TEXT_FILE || return 1

  if [ "$SHUNT_PROVIDER" = anthropic ]; then
    url="$SHUNT_BASE_URL/v1/messages"
    shunt_headers "$headers" "x-api-key: $SHUNT_API_KEY" "anthropic-version: 2023-06-01" "content-type: application/json"
    jq -n \
      --arg model "$SHUNT_MODEL" \
      --argjson max_tokens "$SHUNT_MAX_TOKENS" \
      --arg temperature "$SHUNT_TEMPERATURE" \
      --rawfile system "$system_file" \
      --rawfile message "$message_file" \
      '{model: $model, max_tokens: $max_tokens, system: $system,
        messages: [{role: "user", content: $message}]}
       + (if $temperature == "" then {} else {temperature: ($temperature | tonumber)} end)' >"$payload"
  else
    url="$SHUNT_BASE_URL/chat/completions"
    shunt_headers "$headers" "authorization: Bearer $SHUNT_API_KEY" "content-type: application/json"
    jq -n \
      --arg model "$SHUNT_MODEL" \
      --argjson max_tokens "$SHUNT_MAX_TOKENS" \
      --arg temperature "$SHUNT_TEMPERATURE" \
      --rawfile system "$system_file" \
      --rawfile message "$message_file" \
      '{model: $model, max_completion_tokens: $max_tokens,
        messages: [{role: "system", content: $system}, {role: "user", content: $message}]}
       + (if $temperature == "" then {} else {temperature: ($temperature | tonumber)} end)' >"$payload"
  fi

  if ! status=$(curl -sS -o "$response" -w '%{http_code}' \
    --max-time "$SHUNT_TIMEOUT_SECONDS" \
    -H @"$headers" \
    --data-binary @"$payload" \
    "$url" 2>&1); then
    echo "Error: request to $url failed: $status" >&2
    return 1
  fi

  if [ "$status" != 200 ]; then
    err=$(jq -r '.error.message // .error // .detail // empty' "$response" 2>/dev/null)
    echo "Error: $url returned HTTP $status${err:+: $err}" >&2
    return 1
  fi

  if [ "$SHUNT_PROVIDER" = anthropic ]; then
    jq -j '[.content[]? | select(.type == "text") | .text] | join("")' "$response" >"$SHUNT_TEXT_FILE"
    SHUNT_INPUT_TOKENS=$(jq -r '.usage.input_tokens // 0' "$response")
    SHUNT_OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // 0' "$response")
    SHUNT_STOP=$(jq -r '.stop_reason // empty' "$response")
    [ "$SHUNT_STOP" = max_tokens ] && SHUNT_STOP=length
  else
    jq -j '.choices[0].message.content // ""' "$response" >"$SHUNT_TEXT_FILE"
    SHUNT_INPUT_TOKENS=$(jq -r '.usage.prompt_tokens // 0' "$response")
    SHUNT_OUTPUT_TOKENS=$(jq -r '.usage.completion_tokens // 0' "$response")
    SHUNT_STOP=$(jq -r '.choices[0].finish_reason // empty' "$response")
  fi

  if [ ! -s "$SHUNT_TEXT_FILE" ]; then
    echo "Error: the worker model returned no text." >&2
    return 1
  fi
  if [ "$SHUNT_STOP" = length ]; then
    echo "Warning: the answer hit SHUNT_MAX_TOKENS ($SHUNT_MAX_TOKENS) and is cut off." >&2
  fi
}

# Records one delegation as a LangSmith run. Never fails the caller.
#   $1 run name  $2 inputs JSON  $3 outputs JSON  $4 start  $5 end
# Sets SHUNT_RUN_ID when the run was recorded. Call it directly, not in a
# command substitution, so its temp files are cleaned up on exit.
shunt_trace() {
  local name="$1" inputs="$2" outputs="$3" start="$4" end="$5"
  local id dotted body headers status inputs_file outputs_file
  SHUNT_RUN_ID=""

  case "$SHUNT_TRACE" in false | 0 | no) return 0 ;; esac
  [ -z "$SHUNT_LANGSMITH_API_KEY" ] && return 0

  id=$(shunt_uuid) || return 0
  dotted="$(printf '%s' "$start" | tr -d ':-' | sed 's/\.//')$id"

  shunt_tmpfile body || return 0
  shunt_tmpfile headers || return 0
  shunt_tmpfile inputs_file || return 0
  shunt_tmpfile outputs_file || return 0
  printf '%s' "$inputs" >"$inputs_file"
  printf '%s' "$outputs" >"$outputs_file"
  shunt_headers "$headers" "x-api-key: $SHUNT_LANGSMITH_API_KEY" "content-type: application/json"

  jq -n \
    --arg id "$id" --arg dotted "$dotted" --arg name "$name" \
    --arg start "$start" --arg end "$end" \
    --arg project "$SHUNT_LANGSMITH_PROJECT" \
    --arg thread "${CLAUDE_CODE_SESSION_ID:-}" \
    --arg provider "$SHUNT_PROVIDER" --arg model "$SHUNT_MODEL" \
    --arg version "$SHUNT_VERSION" \
    --slurpfile inputs "$inputs_file" --slurpfile outputs "$outputs_file" \
    --argjson input_tokens "${SHUNT_INPUT_TOKENS:-0}" \
    --argjson output_tokens "${SHUNT_OUTPUT_TOKENS:-0}" \
    '{
      id: $id, trace_id: $id, dotted_order: $dotted,
      name: $name, run_type: "llm",
      start_time: $start, end_time: $end,
      session_name: $project,
      tags: ["langsmith-shunt"],
      inputs: $inputs[0],
      outputs: ($outputs[0] + {usage_metadata: {
        input_tokens: $input_tokens,
        output_tokens: $output_tokens,
        total_tokens: ($input_tokens + $output_tokens)
      }}),
      extra: {metadata: ({
        ls_provider: $provider,
        ls_model_name: $model,
        shunt_version: $version
      } + (if $thread == "" then {} else {thread_id: $thread} end))}
    }' >"$body" || return 0

  status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    -H @"$headers" --data-binary @"$body" \
    "$LANGSMITH_ENDPOINT/runs" 2>/dev/null)
  # shellcheck disable=SC2034  # SHUNT_RUN_ID is read by the calling script
  case "$status" in
    2??) SHUNT_RUN_ID="$id" ;;
    *) echo "Warning: could not record the LangSmith run (HTTP ${status:-none}); the answer is unaffected." >&2 ;;
  esac
}
