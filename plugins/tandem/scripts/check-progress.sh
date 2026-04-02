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

# Status line only. Reflection happens at Stop hook.
jq -n --arg msg "tandem ${STATUS}" '{"systemMessage": $msg}'

exit 0
