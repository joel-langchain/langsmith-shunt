#!/bin/bash
# Tests for the two PreToolUse hooks. Each case feeds the hook the JSON that
# Claude Code would send and checks for a deny or for no decision.

# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/sub dir" "$FIX/other"
seq 1 600 | sed 's/^/const line = /' >"$FIX/big.ts"
seq 1 100 >"$FIX/small.ts"
seq 1 350 >"$FIX/at-limit.ts"
seq 1 351 >"$FIX/over-limit.ts"
seq 1 600 >"$FIX/sub dir/big.ts"
seq 1 600 >"$FIX/notebook.ipynb"
head -c 40000 /dev/urandom >"$FIX/blob.bin"
printf '\0' >>"$FIX/blob.bin"

# run_hook <hook> <tool_input json> [VAR=value ...]
run_hook() {
  local hook="$1" tool_input="$2"
  shift 2
  jq -n --arg cwd "$FIX" --argjson ti "$tool_input" \
    '{session_id: "test", cwd: $cwd, hook_event_name: "PreToolUse", tool_input: $ti}' |
    env "$@" "$SHUNT/hooks/$hook"
}

# expect <deny|none> <name> <hook> <tool_input json> [VAR=value ...]
expect() {
  local want="$1" name="$2" hook="$3" tool_input="$4" out got
  shift 4
  out=$(run_hook "$hook" "$tool_input" "$@")
  if [ -z "$out" ]; then
    got=none
  elif [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")" = deny ]; then
    got=deny
  else
    got="unexpected output: $out"
  fi
  if [ "$got" = "$want" ]; then pass "$name"; else fail "$name" "want $want, got $got"; fi
}

read_input() { jq -nc --arg p "$1" '{file_path: $p}'; }
bash_input() { jq -nc --arg c "$1" '{command: $c}'; }

echo "check-file-size (Read)"
expect deny "full read of a 600-line file" check-file-size "$(read_input "$FIX/big.ts")"
expect none "100-line file" check-file-size "$(read_input "$FIX/small.ts")"
expect none "exactly at the limit" check-file-size "$(read_input "$FIX/at-limit.ts")"
expect deny "one line over the limit" check-file-size "$(read_input "$FIX/over-limit.ts")"
expect none "read with offset" check-file-size "$(jq -nc --arg p "$FIX/big.ts" '{file_path: $p, offset: 100}')"
expect none "read with limit" check-file-size "$(jq -nc --arg p "$FIX/big.ts" '{file_path: $p, limit: 50}')"
expect none "missing file" check-file-size "$(read_input "$FIX/nope.ts")"
expect none "empty path" check-file-size '{}'
expect none "binary file" check-file-size "$(read_input "$FIX/blob.bin")"
expect none "notebook" check-file-size "$(read_input "$FIX/notebook.ipynb")"
expect deny "relative path resolved against cwd" check-file-size "$(read_input big.ts)"
expect deny "path with a space" check-file-size "$(read_input "$FIX/sub dir/big.ts")"
expect none "SHUNT_DISABLED=1" check-file-size "$(read_input "$FIX/big.ts")" SHUNT_DISABLED=1
expect none "SHUNT_MIN_LINES=1000" check-file-size "$(read_input "$FIX/big.ts")" SHUNT_MIN_LINES=1000
expect deny "non-numeric SHUNT_MIN_LINES falls back to 350" check-file-size "$(read_input "$FIX/big.ts")" SHUNT_MIN_LINES=abc

reason=$(run_hook check-file-size "$(read_input "$FIX/big.ts")" CLAUDE_PLUGIN_ROOT=/plugin/root | jq -r .hookSpecificOutput.permissionDecisionReason)
case "$reason" in
  *'"/plugin/root/scripts/bulk-read" --question "<your question>" --paths "'"$FIX"'/big.ts"'*) pass "deny reason gives the exact bulk-read command" ;;
  *) fail "deny reason gives the exact bulk-read command" "$reason" ;;
esac
reason=$(run_hook check-file-size "$(read_input "$FIX/big.ts")" | jq -r .hookSpecificOutput.permissionDecisionReason)
case "$reason" in
  *'/plugins/langsmith-shunt/scripts/bulk-read"'*) pass "without CLAUDE_PLUGIN_ROOT the path comes from the hook's location" ;;
  *) fail "without CLAUDE_PLUGIN_ROOT the path comes from the hook's location" "$reason" ;;
esac

echo
echo "check-bash-read (Bash)"
expect deny "cat large file" check-bash-read "$(bash_input "cat $FIX/big.ts")"
expect deny "cat -n large file" check-bash-read "$(bash_input "cat -n $FIX/big.ts")"
expect deny "/bin/cat large file" check-bash-read "$(bash_input "/bin/cat $FIX/big.ts")"
expect deny "less large file" check-bash-read "$(bash_input "less $FIX/big.ts")"
expect deny "cat relative path" check-bash-read "$(bash_input "cat big.ts")"
expect deny "cat quoted relative path" check-bash-read "$(bash_input 'cat "big.ts"')"
expect deny "four small files add up to 400 lines" check-bash-read "$(bash_input "cat small.ts small.ts small.ts small.ts")"
expect deny "cat after another command" check-bash-read "$(bash_input "echo start; cat big.ts")"
expect deny "cd then cat" check-bash-read "$(bash_input "cd other && cat ../big.ts")"
expect none "cat small file" check-bash-read "$(bash_input "cat $FIX/small.ts")"
expect none "cat piped to grep" check-bash-read "$(bash_input "cat $FIX/big.ts | grep line")"
expect none "cat redirected to a file" check-bash-read "$(bash_input "cat $FIX/big.ts > $FIX/copy.ts")"
# shellcheck disable=SC2016  # the $( is the point of the case
expect none "cat of a command substitution" check-bash-read "$(bash_input 'cat $(ls *.ts)')"
expect none "cat missing file" check-bash-read "$(bash_input "cat $FIX/nope.ts")"
expect none "cat binary file" check-bash-read "$(bash_input "cat $FIX/blob.bin")"
expect none "head with default 10 lines" check-bash-read "$(bash_input "head $FIX/big.ts")"
expect none "head -n 100" check-bash-read "$(bash_input "head -n 100 $FIX/big.ts")"
expect deny "head -n 500" check-bash-read "$(bash_input "head -n 500 $FIX/big.ts")"
expect deny "head -500" check-bash-read "$(bash_input "head -500 $FIX/big.ts")"
expect deny "head --lines=400" check-bash-read "$(bash_input "head --lines=400 $FIX/big.ts")"
expect none "head -c bytes" check-bash-read "$(bash_input "head -c 100000 $FIX/big.ts")"
expect deny "tail -n +2 prints 599 lines" check-bash-read "$(bash_input "tail -n +2 $FIX/big.ts")"
expect none "tail -n +500 prints 101 lines" check-bash-read "$(bash_input "tail -n +500 $FIX/big.ts")"
expect none "tail -f" check-bash-read "$(bash_input "tail -f $FIX/big.ts")"
expect none "git status" check-bash-read "$(bash_input "git status")"
expect none "bulk-read call" check-bash-read "$(bash_input "\"$SHUNT/scripts/bulk-read\" --question q --paths $FIX/big.ts")"
expect none "SHUNT_DISABLED=true" check-bash-read "$(bash_input "cat $FIX/big.ts")" SHUNT_DISABLED=true

summary
