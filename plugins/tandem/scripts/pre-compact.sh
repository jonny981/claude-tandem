#!/bin/bash
# PreCompact hook: captures current state snapshot + safety-net progress extraction.
# Always captures STATE (what's happening right now) for post-compaction recovery.
# Only captures PROGRESS if progress.md is stale/missing (safety net).
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
INCLUDE_PROGRESS=false
if [ ! -f "$PROGRESS_DIR/progress.md" ]; then
  INCLUDE_PROGRESS=true
else
  PROGRESS_MTIME=$(tandem_file_mtime "$PROGRESS_DIR/progress.md")
  NOW=$(date +%s)
  if [ -n "$PROGRESS_MTIME" ]; then
    AGE=$((NOW - PROGRESS_MTIME))
    [ "$AGE" -gt 120 ] && INCLUDE_PROGRESS=true
  fi
fi

# Check for structured Working State markers (deterministic state capture)
WORKING_STATE=""
if [ -f "$PROGRESS_DIR/progress.md" ]; then
  WORKING_STATE=$(sed -n '/<!-- working-state:start -->/,/<!-- working-state:end -->/p' \
    "$PROGRESS_DIR/progress.md" 2>/dev/null | grep -v '<!-- working-state')
fi

# If structured state exists and progress is fresh, skip LLM entirely
if [ -n "$WORKING_STATE" ] && [ "$INCLUDE_PROGRESS" = false ]; then
  # Structured state found + progress is fresh — write state directly, no LLM needed
  mkdir -p "$PROGRESS_DIR"
  TMPFILE=$(mktemp)
  if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
    tandem_log error "failed to create temp file for progress.md"
    exit 0
  fi

  if [ -f "$PROGRESS_DIR/progress.md" ]; then
    cat "$PROGRESS_DIR/progress.md" > "$TMPFILE"
  fi

  printf '\n## Pre-compaction State\n' >> "$TMPFILE"
  echo "$WORKING_STATE" >> "$TMPFILE"

  mv "$TMPFILE" "$PROGRESS_DIR/progress.md"
  tandem_log info "captured structured working state before compaction (no LLM)"
  exit 0
fi

# Build haiku prompt
PROGRESS_INSTRUCTION=""
if [ "$INCLUDE_PROGRESS" = true ]; then
  PROGRESS_INSTRUCTION="
PROGRESS:
What was worked on during this session? Key decisions made and their rationale? Output 3-8 bullet points covering the session broadly."
fi

PROMPT="You are a session state extractor. The following is a portion of a Claude Code session transcript (JSONL format).

If the transcript shows trivial activity (just reading files, no real work), output exactly: SKIP

Otherwise, extract the following:

STATE:
What is the user working on RIGHT NOW? What was their most recent request? What is Claude about to do next? Any pending decisions or unresolved questions? Output 3-5 bullet points capturing the precise current position.
${PROGRESS_INSTRUCTION}

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

# Extract STATE section
STATE_CONTENT=$(echo "$RESULT" | sed -n '/^STATE:/,/^PROGRESS:/{ /^PROGRESS:/d; p; }')
# If no PROGRESS section follows, grab STATE to end
if [ -z "$STATE_CONTENT" ]; then
  STATE_CONTENT=$(echo "$RESULT" | sed -n '/^STATE:/,$p')
fi

# Extract PROGRESS section (only present if stale)
PROGRESS_CONTENT=""
if [ "$INCLUDE_PROGRESS" = true ]; then
  PROGRESS_CONTENT=$(echo "$RESULT" | sed -n '/^PROGRESS:/,$p')
fi

# Append to progress.md via temp file
TMPFILE=$(mktemp)
if [ -z "$TMPFILE" ] || [ ! -f "$TMPFILE" ]; then
  tandem_log error "failed to create temp file for progress.md"
  exit 0
fi

if [ -f "$PROGRESS_DIR/progress.md" ]; then
  cat "$PROGRESS_DIR/progress.md" > "$TMPFILE"
fi

# Append progress section if present
if [ -n "$PROGRESS_CONTENT" ]; then
  printf '\n## Auto-captured (pre-compaction)\n' >> "$TMPFILE"
  echo "$PROGRESS_CONTENT" | sed '1s/^PROGRESS://' >> "$TMPFILE"
fi

# Always append state section
if [ -n "$STATE_CONTENT" ]; then
  printf '\n## Pre-compaction State\n' >> "$TMPFILE"
  echo "$STATE_CONTENT" | sed '1s/^STATE://' >> "$TMPFILE"
fi

if [ $? -ne 0 ]; then
  tandem_log error "failed to write progress.md temp file"
  rm -f "$TMPFILE"
  exit 0
fi

mv "$TMPFILE" "$PROGRESS_DIR/progress.md"
tandem_log info "captured state before compaction"

exit 0
