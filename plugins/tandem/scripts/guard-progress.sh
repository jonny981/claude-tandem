#!/bin/bash
# PreToolUse hook: blocks Write/Edit when progress.md is template-only.
# Allows writes TO progress.md (otherwise we'd deadlock).
# This is the hard enforcement — Claude cannot ignore a block decision.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# If the file being written IS progress.md, always allow (don't deadlock)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE_PATH" in
  *progress.md) exit 0 ;;
esac

# Compute progress directory
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

# If progress.md doesn't exist or is template-only, block
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  jq -n '{decision: "block", reason: "progress.md does not exist. Write your Working State to progress.md first (current task, approach, key files), then retry this action."}'
  exit 2
fi

if grep -q '\[what you'"'"'re actively doing\]' "$PROGRESS_DIR/progress.md" 2>/dev/null; then
  jq -n '{decision: "block", reason: "progress.md is still a blank template. Write your Working State to progress.md first (current task, approach, key files), then retry this action."}'
  exit 2
fi

# progress.md is populated — allow
exit 0
