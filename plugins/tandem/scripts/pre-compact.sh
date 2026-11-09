#!/bin/bash
# PreCompact hook: safety-net progress extraction before context compaction.
# If progress.md is stale/missing, uses LLM to extract session state from transcript.
# Outputs nothing to stdout — writes directly to progress.md.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[ -z "$CWD" ] && exit 0
[ -z "$TRANSCRIPT_PATH" ] && exit 0
[ ! -f "$TRANSCRIPT_PATH" ] && exit 0

# Compute progress directory
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

# Read tail of transcript (last ~20KB)
TRANSCRIPT_TAIL=$(tail -c 20000 "$TRANSCRIPT_PATH" 2>/dev/null)
[ -z "$TRANSCRIPT_TAIL" ] && exit 0

# Determine if progress.md is stale (> 2 minutes old or missing)
NEEDS_EXTRACTION=false
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  NEEDS_EXTRACTION=true
else
  PROGRESS_MTIME=$(tandem_file_mtime "$PROGRESS_DIR/progress.md")
  NOW=$(date +%s)
  if [ -n "$PROGRESS_MTIME" ]; then
    AGE=$((NOW - PROGRESS_MTIME))
    [ "$AGE" -gt 120 ] && NEEDS_EXTRACTION=true
  fi
fi

# If progress is fresh, just append a compaction marker
if [ "$NEEDS_EXTRACTION" = false ]; then
  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    cat "$PROGRESS_DIR/progress.md" > "$TMPFILE"
    printf '\n## Pre-compaction marker\nContext compaction occurred here.\n' >> "$TMPFILE"
    mv "$TMPFILE" "$PROGRESS_DIR/progress.md"
    tandem_log info "appended compaction marker (progress was fresh)"
  fi
  exit 0
fi

# Build haiku prompt for extraction
PROMPT="You are a session state extractor. The following is a portion of a Claude Code session transcript (JSONL format).

If the transcript shows trivial activity (just reading files, no real work), output exactly: SKIP

Otherwise, extract:

STATE:
What is the user working on RIGHT NOW? What was their most recent request? What is Claude about to do next? Any pending decisions or unresolved questions? Output 3-5 bullet points capturing the precise current position.

PROGRESS:
What was worked on during this session? Key decisions made and their rationale? Output 3-8 bullet points covering the session broadly.

Focus on WHAT and WHY, not HOW. Be specific — names, file paths, step numbers.

<transcript>
${TRANSCRIPT_TAIL}
</transcript>"

# Call LLM
tandem_require_llm || exit 0

RESULT=$(TANDEM_WORKER=1 tandem_llm_call "$PROMPT")

if [ $? -ne 0 ] || [ -z "$RESULT" ]; then
  tandem_log warn "pre-compaction state capture failed"
  exit 0
fi

# Check for SKIP
if echo "$RESULT" | grep -qx 'SKIP'; then
  tandem_log debug "pre-compaction skipped (trivial activity)"
  exit 0
fi

# Parse and append to progress.md
mkdir -p "$PROGRESS_DIR"

# Create progress.md with frontmatter if missing
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  cat > "$PROGRESS_DIR/progress.md" <<'TEMPLATE'
---
framework: default
type: session-progress
depends_on: []
feeds: [MEMORY.md]
---
TEMPLATE
fi

# Extract STATE and PROGRESS sections
STATE_CONTENT=$(echo "$RESULT" | sed -n '/^STATE:/,/^PROGRESS:/{ /^PROGRESS:/d; p; }')
if [ -z "$STATE_CONTENT" ]; then
  STATE_CONTENT=$(echo "$RESULT" | sed -n '/^STATE:/,$p')
fi

PROGRESS_CONTENT=$(echo "$RESULT" | sed -n '/^PROGRESS:/,$p')

# Append to progress.md via temp file
TMPFILE=$(mktemp)
if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
  tandem_log error "failed to create temp file for progress.md"
  exit 0
fi

cat "$PROGRESS_DIR/progress.md" > "$TMPFILE"

if [ -n "$PROGRESS_CONTENT" ]; then
  printf '\n## Auto-captured (pre-compaction)\n' >> "$TMPFILE"
  echo "$PROGRESS_CONTENT" | sed '1s/^PROGRESS://' >> "$TMPFILE"
fi

if [ -n "$STATE_CONTENT" ]; then
  printf '\n## Pre-compaction State\n' >> "$TMPFILE"
  echo "$STATE_CONTENT" | sed '1s/^STATE://' >> "$TMPFILE"
fi

mv "$TMPFILE" "$PROGRESS_DIR/progress.md"
tandem_log info "captured state before compaction"

exit 0
