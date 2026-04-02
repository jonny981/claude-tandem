#!/bin/bash
# SessionEnd hook: lightweight session bookkeeping.
# Sync hook — no background workers, no LLM calls.
# Compaction is now handled inline by Claude via the post-commit hook.
#
# Responsibilities:
#   1. Print session summary to user
#   2. Update recurrence.json with themes from MEMORY.md
#   3. Update global.md cross-project log
#   4. Deregister session and write recap

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
_TANDEM_SCRIPT="session-end"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Capture session_id for deregistration
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && SESSION_ID="${TANDEM_SESSION_ID:-}"

# Compute paths
MEMORY_DIR=$(tandem_memory_dir "$CWD")
PROGRESS_DIR=$(tandem_progress_dir "$CWD")
STATE_DIR="$HOME/.tandem/state"
RECURRENCE_FILE="$STATE_DIR/recurrence.json"
TODAY=$(date +%Y-%m-%d)

# Exit early if no progress.md (trivial session)
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  tandem_session_deregister "${SESSION_ID}"
  exit 0
fi

# ─── 1. Inform user ─────────────────────────────────────────────────────────

PROGRESS_LINES=$(wc -l < "$PROGRESS_DIR/progress.md" | tr -d ' ')
tandem_print "Session ended (${PROGRESS_LINES} lines captured)."
tandem_log info "session end: ${PROGRESS_LINES} lines of progress"

# ─── 2. Update recurrence.json with themes from MEMORY.md ───────────────────

THEMES_LINE=""
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  THEMES_LINE=$(tail -1 "$MEMORY_DIR/MEMORY.md")
  if [[ "$THEMES_LINE" != THEMES:* ]]; then
    THEMES_LINE=""
  fi
fi

if [ -n "$THEMES_LINE" ]; then
  THEMES_RAW="${THEMES_LINE#THEMES: }"
  mkdir -p "$STATE_DIR"

  if [ -f "$RECURRENCE_FILE" ]; then
    RECURRENCE=$(cat "$RECURRENCE_FILE")
  else
    RECURRENCE='{"themes":{}}'
  fi

  IFS=',' read -ra THEME_ARRAY <<< "$THEMES_RAW"
  for theme in "${THEME_ARRAY[@]}"; do
    theme=$(echo "$theme" | xargs)
    [ -z "$theme" ] && continue

    EXISTING_COUNT=$(echo "$RECURRENCE" | jq -r ".themes[\"$theme\"].count // 0" 2>/dev/null)
    if [ $? -ne 0 ] || ! [[ "$EXISTING_COUNT" =~ ^[0-9]+$ ]]; then
      tandem_log warn "jq parse failed for theme $theme, skipping"
      continue
    fi

    if [ "$EXISTING_COUNT" -gt 0 ]; then
      RECURRENCE=$(echo "$RECURRENCE" | jq \
        --arg t "$theme" \
        --arg d "$TODAY" \
        '.themes[$t].count += 1 | .themes[$t].last_seen = $d' 2>/dev/null)
    else
      RECURRENCE=$(echo "$RECURRENCE" | jq \
        --arg t "$theme" \
        --arg d "$TODAY" \
        '.themes[$t] = {"count": 1, "first_seen": $d, "last_seen": $d}' 2>/dev/null)
    fi

    if [ $? -ne 0 ] || [ -z "$RECURRENCE" ]; then
      tandem_log warn "jq update failed for theme $theme"
      RECURRENCE='{"themes":{}}'
      break
    fi
  done

  TMPFILE=$(mktemp "$STATE_DIR/recurrence.json.XXXXXX")
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    if echo "$RECURRENCE" > "$TMPFILE" && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$RECURRENCE_FILE"
    else
      tandem_log warn "failed to write recurrence.json"
      rm -f "$TMPFILE"
    fi
  fi
fi

# ─── 3. Cross-project activity log ──────────────────────────────────────────

PROJECT_NAME=$(basename "$CWD")
GLOBAL_DIR="$HOME/.tandem/memory"
GLOBAL_FILE="$GLOBAL_DIR/global.md"

SUMMARY=$(grep -v '^\s*$' "$PROGRESS_DIR/progress.md" | grep -v '^#' | head -3 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-120)

if [ -n "$SUMMARY" ]; then
  ENTRY="## ${TODAY} — ${PROJECT_NAME}
${SUMMARY}
"
  mkdir -p "$GLOBAL_DIR"

  DEDUP_HEADER="## ${TODAY} — ${PROJECT_NAME}"
  if [ -f "$GLOBAL_FILE" ]; then
    FIRST_HEADER=$(head -1 "$GLOBAL_FILE")
    if [ "$FIRST_HEADER" = "$DEDUP_HEADER" ]; then
      EXISTING_TAIL=$(awk 'NR==1{next} /^## /{found=1} found{print}' "$GLOBAL_FILE")
    else
      EXISTING_TAIL=$(cat "$GLOBAL_FILE")
    fi
  else
    EXISTING_TAIL=""
  fi

  TMPFILE=$(mktemp "$GLOBAL_DIR/global.md.XXXXXX")
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    {
      printf '%s\n' "$ENTRY"
      [ -n "$EXISTING_TAIL" ] && printf '%s\n' "$EXISTING_TAIL"
    } | awk '
      /^## / { count++ }
      count <= 30 { print }
    ' > "$TMPFILE"

    if [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$GLOBAL_FILE"
      tandem_log info "cross-project activity logged"
    else
      rm -f "$TMPFILE"
    fi
  fi
fi

# ─── 4. Deregister session and write recap ───────────────────────────────────

tandem_session_deregister "${SESSION_ID}"

RECAP_FILE="$HOME/.tandem/.last-session-recap"
cat > "$RECAP_FILE" <<RECAP_EOF
date: $TODAY
recall_status: inline
global_status: 1
RECAP_EOF

if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  LINE_COUNT=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
  echo "memory_lines: $LINE_COUNT" >> "$RECAP_FILE"
fi

# Clean up completed-tasks accumulator for next session
rm -f "$STATE_DIR/completed-tasks.jsonl"

exit 0
