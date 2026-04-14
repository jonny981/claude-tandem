#!/bin/bash
# UserPromptSubmit hook: status line with file ages.
# No nudging — reflection and progress.md creation happen at Stop.
# No LLM call — just file stat checks.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Compute directories
MEMORY_DIR=$(tandem_memory_dir "$CWD")
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

# Compute file ages
MEM_AGE="-"
PROG_AGE="-"
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  MEM_AGE=$(_tandem_relative_age "$(tandem_file_mtime "$MEMORY_DIR/MEMORY.md")")
fi
if [ -f "$PROGRESS_DIR/progress.md" ]; then
  PROG_AGE=$(_tandem_relative_age "$(tandem_file_mtime "$PROGRESS_DIR/progress.md")")
fi

# Project name and modified file count
PROJECT=$(basename "$CWD")
MODIFIED=0
if git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
  MODIFIED=$(git -C "$CWD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

STATUS="${PROJECT} · mem:${MEM_AGE} prog:${PROG_AGE} mod:${MODIFIED}"

# ─── Stale compaction check ────────────────────────────────────────────
# If the last commit is newer than progress.md and progress.md still has
# session log content, compaction was skipped. Block until resolved.
COMPACTION_WARNING=""
if [ -f "$PROGRESS_DIR/progress.md" ] && git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
  LAST_COMMIT_TIME=$(git -C "$CWD" log -1 --format=%ct 2>/dev/null || echo 0)
  PROGRESS_MTIME=$(tandem_file_mtime "$PROGRESS_DIR/progress.md")

  # Check if progress.md has session log content (lines after working-state:end marker)
  SESSION_LOG_LINES=$(sed -n '/working-state:end/,$p' "$PROGRESS_DIR/progress.md" 2>/dev/null | grep -v '^$' | grep -v 'working-state:end' | wc -l | tr -d ' ')

  if [ "$LAST_COMMIT_TIME" -gt "$PROGRESS_MTIME" ] 2>/dev/null && [ "$SESSION_LOG_LINES" -gt 0 ] 2>/dev/null; then
    COMPACTION_WARNING="STALE COMPACTION: A commit was made after the last progress.md update, but progress.md still has ${SESSION_LOG_LINES} lines of session log. This means compaction was skipped. Run compaction NOW before doing anything else: (1) Merge session learnings from progress.md into MEMORY.md. (2) Reset progress.md session log. (3) Update Working State for current task. "
  fi
fi

# Build output
MSG="tandem ${STATUS}"
if [ -n "$COMPACTION_WARNING" ]; then
  MSG="${COMPACTION_WARNING}${MSG}"
fi

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'

exit 0
