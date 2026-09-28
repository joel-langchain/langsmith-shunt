# Shared helpers for the langsmith-shunt PreToolUse hooks.
#
# The hooks fail open: a missing jq, an unreadable path, or anything they
# cannot parse ends with no output, which leaves the decision to Claude Code's
# normal permission flow. They only ever emit a deny, never an allow, so they
# cannot approve a tool call the user would otherwise be asked about.

SHUNT_MIN_LINES="${SHUNT_MIN_LINES:-350}"
case "$SHUNT_MIN_LINES" in '' | *[!0-9]*) SHUNT_MIN_LINES=350 ;; esac

shunt_hooks_enabled() {
  case "${SHUNT_DISABLED:-}" in 1 | true | TRUE | yes) return 1 ;; esac
  command -v jq >/dev/null 2>&1
}

# Prints the absolute path of a tool argument, resolved against a base
# directory. Fails when the file does not exist or cannot be read.
shunt_resolve_path() {
  local p="$1" base="$2"
  [ -z "$p" ] && return 1
  # shellcheck disable=SC2088  # matching a literal ~ from the tool input
  case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) ;; *) [ -n "$base" ] && p="$base/$p" ;; esac
  [ -f "$p" ] && [ -r "$p" ] || return 1
  printf '%s\n' "$p"
}

# True for plain text files. Read renders images, PDFs, and notebooks itself,
# so those are left alone.
shunt_is_text() {
  case "$1" in *.ipynb | *.pdf) return 1 ;; esac
  LC_ALL=C grep -Iq . "$1" 2>/dev/null
}

shunt_line_count() {
  wc -l <"$1" 2>/dev/null | tr -d ' '
}

# Denies the tool call. The reason is shown to Claude, not to the user.
shunt_deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}
