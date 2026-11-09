#!/bin/bash
# PreToolUse hook: blocks raw git commit, enforces /tandem:commit usage.
# The /tandem:commit skill runs the full memory pipeline (commit + compaction).
# Fires on Bash tool calls. Exits 0 (allow) or 2 (deny with reason).

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

# Quiet mode: do not gate raw git commit; the commit-body rule still applies.
[ -n "${TANDEM_QUIET:-}" ] || [ -f "$HOME/.tandem/quiet" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only care about Bash tool calls
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Only care about a real commit command: `git commit`, `git --no-pager commit`,
# `git -C path commit`, at the start of the command or after ; && || | ( $( or a
# newline. Prose that merely mentions the phrase (a heredoc body, an echo) is
# not a commit and must not be blocked.
GIT_COMMIT_RE=$'(^|[;&|(]|\\$\\(|\n)[[:space:]]*(sudo[[:space:]]+)?git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'
[[ "$COMMAND" =~ $GIT_COMMIT_RE ]] || exit 0

# ─── The /tandem:commit skill's seam ───────────────────────────────────
# The skill cannot set TANDEM_WORKER (that env belongs to the hook's own
# process), so it declares intent by touching a one-shot sentinel right
# before running git commit. A fresh sentinel authorizes the commit;
# post-commit.sh consumes it. Staleness bounds a leaked sentinel.
SENTINEL="$HOME/.tandem/commit-intent"
if [ -f "$SENTINEL" ] && [ -n "$(find "$SENTINEL" -mmin -15 2>/dev/null)" ]; then
  tandem_log info "allowed: commit-intent sentinel present"
  exit 0
fi

# ─── Enforce /tandem:commit usage ──────────────────────────────────────
# Block raw git commit and redirect to the Tandem commit skill.
# The skill runs the full pipeline: structured commit body, compaction,
# MEMORY.md update.

REASON="Do not use raw git commit. Use /tandem:commit instead.

The /tandem:commit skill runs the full memory pipeline:
1. Structured epistemic commit body (from progress.md session log)
2. Compaction: merge learnings from progress.md into MEMORY.md
3. Reset progress.md session log

Raw git commit bypasses all of this and session knowledge is lost.

Invoke the Skill tool with skill: \"tandem:commit\" now."

tandem_log info "denied: raw git commit, must use /tandem:commit"
jq -n --arg reason "$REASON" '{"decision": "deny", "reason": $reason}'
exit 2
