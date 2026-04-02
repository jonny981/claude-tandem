#!/bin/bash
# PostToolUse hook: detects successful git commits and triggers inline compaction.
# Claude does the compaction with full session context — no background LLM calls.
# Also instructs Claude to mine recent commit history for recurring patterns.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)

# Only fire on Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" != "Bash" ] && exit 0

# Check command contains git commit
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
case "$COMMAND" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Skip amends (not a new work boundary)
case "$COMMAND" in
  *"--amend"*) exit 0 ;;
esac

# Skip if commit failed (check for error indicators in output)
TOOL_ERROR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty')
if echo "$TOOL_ERROR" | grep -qi "nothing to commit\|no changes added\|aborting commit"; then
  exit 0
fi

# Compute progress directory
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

# Build the compaction systemMessage
PROGRESS_WARNING=""
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  PROGRESS_WARNING="WARNING: progress.md does not exist. The compaction pipeline has nothing to work with. Create progress.md with your Working State immediately. "
elif grep -q '\[what you'"'"'re actively doing\]' "$PROGRESS_DIR/progress.md" 2>/dev/null; then
  PROGRESS_WARNING="WARNING: progress.md is still a blank template. Fill in your Working State before compacting. "
fi

tandem_log info "post-commit: triggering inline compaction"

MSG="${PROGRESS_WARNING}COMPACTION REQUIRED. A commit was just made. Run the full pipeline now, do not defer: (1) Read progress.md and MEMORY.md. (2) Merge relevant session learnings from progress.md into MEMORY.md using priority tiers ([P1] permanent, [P2] active, [P3] ephemeral), stay under 200 lines. (3) Run git log --format='%B' -10 and look for recurring patterns across commits. Promote to CLAUDE.md if a pattern appears in 3+ commits. (4) Reset progress.md: preserve frontmatter and Working State template markers, clear Session Log, reset Working State fields to placeholders. This is the memory pipeline boundary. Skipping it means session knowledge is lost."

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'

exit 0
