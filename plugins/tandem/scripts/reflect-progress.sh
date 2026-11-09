#!/bin/bash
# Stop hook: prompt Claude to reflect on the work done and capture it in progress.md.
# This fires when Claude finishes responding — the natural moment to reflect.
# Creates progress.md if it doesn't exist. No LLM call.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Read the stop reason to understand context
STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // empty')

# Only reflect on substantive stops (end_turn means Claude finished a response)
case "$STOP_REASON" in
  end_turn) ;;  # Claude finished responding — good time to reflect
  *) exit 0 ;;  # Tool use, interruption, etc — not a reflection point
esac

# Compute progress directory
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

# Create progress.md if it doesn't exist
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  mkdir -p "$PROGRESS_DIR"
  cat > "$PROGRESS_DIR/progress.md" <<'TEMPLATE'
---
framework: default
type: session-progress
depends_on: []
feeds: [MEMORY.md]
---
TEMPLATE
  tandem_log info "progress.md created at $PROGRESS_DIR"
fi

jq -n '{
  "systemMessage": "Reflect: did you just make a decision, change approach, hit a constraint, or finish a meaningful chunk? If so, append the reasoning to progress.md. If the work was trivial or you are still accumulating context, skip."
}'

exit 0
