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

<!-- working-state:start -->
## Working State
**Current task:** [what you're actively doing]
**Approach:** [chosen approach and why]
**Blockers:** [unresolved issues, if any]
**Key files:** [files being modified]
<!-- working-state:end -->
TEMPLATE
  tandem_log info "progress.md created at $PROGRESS_DIR"
fi

# If progress.md is template-only, prompt to populate it
if grep -q '\[what you'"'"'re actively doing\]' "$PROGRESS_DIR/progress.md" 2>/dev/null; then
  jq -n '{
    "systemMessage": "Reflect: progress.md exists but is empty. If the work you just completed was substantive, write your Working State now (current task, approach, key files) and a brief session log entry."
  }'
  exit 0
fi

jq -n '{
  "systemMessage": "Update progress.md if the work just completed was substantive: new direction, key decision, or completed chunk. Skip if trivial continuation."
}'

exit 0
