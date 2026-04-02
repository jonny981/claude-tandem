#!/bin/bash
# TaskCompleted hook (async): reflection trigger for progress.md writes.
# Accumulates completed task subjects and asks Claude to evaluate whether
# progress.md needs updating. The judgment is Claude's; this hook provides
# the evidence and reliably triggers the evaluation.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty')
[ -z "$CWD" ] && exit 0

# Compute progress directory
PROGRESS_DIR=$(tandem_progress_dir "$CWD")
STATE_DIR="$HOME/.tandem/state"
TASKS_FILE="$STATE_DIR/completed-tasks.jsonl"
NOW=$(date +%s)

# Accumulate this task
if [ -n "$TASK_SUBJECT" ]; then
  mkdir -p "$STATE_DIR"
  jq -n --arg s "$TASK_SUBJECT" --argjson t "$NOW" '{subject: $s, ts: $t}' >> "$TASKS_FILE" 2>/dev/null
fi

# Case 1: progress.md missing or template-only — strong nudge
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  tandem_log info "progress.md missing after task completion"
  echo '{"systemMessage": "progress.md does not exist. Before continuing, create it in your auto-memory directory with your Working State: what you are working on, your approach, blockers, and key files. The memory pipeline depends on this file."}'
  exit 0
fi

if grep -q '\[what you'"'"'re actively doing\]' "$PROGRESS_DIR/progress.md" 2>/dev/null; then
  tandem_log info "progress.md template-only after task completion"
  echo '{"systemMessage": "progress.md is still a blank template. Fill in your Working State now with what you are working on, your approach, and key files."}'
  exit 0
fi

# Case 2: Gather tasks completed since last progress.md write
PROGRESS_MTIME=$(tandem_file_mtime "$PROGRESS_DIR/progress.md")
[ -z "$PROGRESS_MTIME" ] && PROGRESS_MTIME=0

RECENT_TASKS=""
if [ -f "$TASKS_FILE" ]; then
  RECENT_TASKS=$(jq -r --argjson since "$PROGRESS_MTIME" \
    'select(.ts > $since) | .subject' "$TASKS_FILE" 2>/dev/null | head -10)
fi

# If no accumulated tasks since last write, check simple staleness
if [ -z "$RECENT_TASKS" ]; then
  AGE=$((NOW - PROGRESS_MTIME))
  if [ "$AGE" -le 300 ]; then
    tandem_log debug "progress fresh, no nudge needed"
    exit 0
  fi
  # Stale but no accumulated tasks — generic nudge
  SUBJECT_MSG=""
  if [ -n "$TASK_SUBJECT" ]; then
    SUBJECT_MSG="Task '${TASK_SUBJECT}' was just completed. "
  fi
  echo "{\"systemMessage\": \"${SUBJECT_MSG}progress.md hasn't been updated in $((AGE / 60)) minutes. Evaluate: has your Working State changed (new task, different approach, decisions made, blockers resolved, key files changed)? If yes, update progress.md now.\"}"
  exit 0
fi

# Format the accumulated task list
TASK_LIST=$(echo "$RECENT_TASKS" | sed 's/^/- /' | tr '\n' ' ' | sed 's/ *$//')

tandem_log debug "reflection trigger: $(echo "$RECENT_TASKS" | wc -l | tr -d ' ') tasks since last write"

MSG="Tasks completed since your last progress.md update: ${TASK_LIST}. Evaluate: do these represent a significant change in your Working State (new task, changed approach, decisions made, blockers resolved, key files changed)? If yes, update progress.md now. If not, carry on."
jq -n --arg msg "$MSG" '{"systemMessage": $msg}'

exit 0
