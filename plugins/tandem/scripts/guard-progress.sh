#!/bin/bash
# PreToolUse hook: blocks Edit/Write when progress.md is empty or stale.
# Allows writes TO progress.md and MEMORY.md (otherwise we'd deadlock).
# This is hard enforcement — Claude cannot ignore a block decision.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# If the file being written IS progress.md or MEMORY.md, always allow
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE_PATH" in
  *progress.md|*MEMORY.md) exit 0 ;;
esac

# Compute progress directory
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

# Block 1: progress.md missing
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  jq -n '{decision: "block", reason: "progress.md does not exist. Create it and append your first session log entry (what you are about to do, why, what constraints shape the approach) before editing files."}'
  exit 2
fi

# Block 2: progress.md has no content after frontmatter
# Count non-empty lines after the closing --- of frontmatter
CONTENT_LINES=$(awk '
  BEGIN { in_fm=0; past_fm=0 }
  /^---$/ { if (!in_fm) { in_fm=1; next } else { past_fm=1; next } }
  past_fm && /[^ \t]/ { count++ }
  END { print count+0 }
' "$PROGRESS_DIR/progress.md")

if [ "$CONTENT_LINES" -eq 0 ]; then
  jq -n '{decision: "block", reason: "progress.md is empty. Append your first session log entry (what you are about to do, why, what constraints shape the approach) before editing files."}'
  exit 2
fi

# All checks pass — allow
exit 0
