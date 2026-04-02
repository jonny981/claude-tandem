#!/usr/bin/env bats
# Integration: end-to-end lifecycle journeys
# Tests multi-hook flows that span session-start, task-completed,
# pre-compact, session-end in sequence.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Minimal session-start setup (ensure provisioned so we skip first-run noise)
_provision() {
  mkdir -p "$HOME/.tandem"
  date +%s > "$HOME/.tandem/.provisioned"
  mkdir -p "$HOME/.claude"
  echo '{}' > "$HOME/.claude/settings.json"
  # Ensure CLAUDE.md exists with tandem section so session-start doesn't create it
  cat > "$HOME/.claude/CLAUDE.md" <<'MD'
<!-- tandem:start v1.2.1 -->
## Tandem — Session Progress
Placeholder
<!-- tandem:end -->
MD
}

# Create a fake transcript file for pre-compact
_create_transcript() {
  local path="$1"
  # Minimal JSONL so pre-compact has something to read
  echo '{"type":"user","content":"working on auth"}' > "$path"
  echo '{"type":"assistant","content":"implementing JWT"}' >> "$path"
}

# ─── Tests ────────────────────────────────────────────────────────────────────

@test "lifecycle: start -> task-completed nudge -> pre-compact -> start resume" {
  _provision

  # 1. Session start (startup)
  run_script_with_input "session-start.sh" '{"cwd":"'"$TEST_CWD"'","source":"startup"}'
  assert_success
  # Should show header
  assert_output --partial "Tandem"

  # 2. Create stale progress.md (6 minutes old)
  create_progress "- Implemented user login endpoint" 360

  # 3. Task completed should nudge (progress is stale)
  run_script_with_input "task-completed.sh" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  # Output should be a JSON systemMessage
  echo "$output" | jq empty
  assert_output --partial "systemMessage"
  assert_output --partial "progress.md"

  # 4. Pre-compact with mock LLM returning state
  _install_mock_claude_fixture "precompact-state-only.txt"

  local transcript="$TEST_TEMP_DIR/transcript.jsonl"
  _create_transcript "$transcript"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"
  assert_success

  # progress.md should now have Pre-compaction State section
  grep -q '## Pre-compaction State' "$TEST_PROGRESS_DIR/progress.md"

  # 5. Session start again (resume) should recover state and strip the section
  run_script_with_input "session-start.sh" '{"cwd":"'"$TEST_CWD"'","source":"resume"}'
  assert_success
  assert_output --partial "Resuming"
  assert_output --partial "JWT token generation"

  # State section should be stripped from progress.md
  ! grep -q '## Pre-compaction State' "$TEST_PROGRESS_DIR/progress.md"
}

@test "lifecycle: start -> session-end writes recap -> next start shows recap" {
  _provision

  # 1. Session start
  run_script_with_input "session-start.sh" '{"cwd":"'"$TEST_CWD"'","source":"startup"}'
  assert_success

  # 2. Create progress.md with content
  create_progress "- Built user auth module
- Added JWT token generation
- Wrote integration tests for login flow"

  # 3. Run simplified session-end (no worker, just summary + bookkeeping)
  run_script_with_input "session-end.sh" "$(fixture_sessionend "$TEST_CWD")"
  assert_success
  assert_output --partial "Session ended"

  # Recap file should be created
  [ -f "$HOME/.tandem/.last-session-recap" ]
  grep -q 'recall_status: inline' "$HOME/.tandem/.last-session-recap"

  # 4. Next session start should show recap
  run_script_with_input "session-start.sh" '{"cwd":"'"$TEST_CWD"'","source":"startup"}'
  assert_success

  # Recap file should be consumed (deleted)
  [ ! -f "$HOME/.tandem/.last-session-recap" ]
}

@test "lifecycle: pre-compaction state written and consumed on resume" {
  _provision

  # Create progress.md with a Pre-compaction State section already present
  # (simulates what pre-compact.sh would have written)
  cat > "$TEST_PROGRESS_DIR/progress.md" <<'PROGRESS'
- Earlier work notes

## Pre-compaction State
- Working on database migration scripts
- Just finished schema for users table
- About to write seed data
PROGRESS

  # Session start (resume/compact) should detect and output state
  run_script_with_input "session-start.sh" '{"cwd":"'"$TEST_CWD"'","source":"compact"}'
  assert_success
  assert_output --partial "Resuming"
  assert_output --partial "database migration"
  assert_output --partial "seed data"

  # The Pre-compaction State section should be stripped
  ! grep -q '## Pre-compaction State' "$TEST_PROGRESS_DIR/progress.md"

  # Earlier notes should still be present
  grep -q 'Earlier work notes' "$TEST_PROGRESS_DIR/progress.md"
}

@test "lifecycle: MEMORY.md corruption detected and rolled back from backup" {
  _provision

  # Create a backup of the good MEMORY.md
  local good_content="# Project Memory

## Architecture
- Express + TypeScript API
- PostgreSQL with Prisma

## Last Session
Working on auth endpoints."

  create_memory "$good_content"
  cp "$TEST_MEMORY_DIR/MEMORY.md" "$TEST_MEMORY_DIR/.MEMORY.md.backup-$(date +%s)"

  # Corrupt MEMORY.md with a refusal pattern
  echo "I'm sorry, but I cannot help with that request." > "$TEST_MEMORY_DIR/MEMORY.md"

  # Session start should detect corruption and roll back
  run_script_with_input "session-start.sh" '{"cwd":"'"$TEST_CWD"'","source":"startup"}'
  assert_success
  assert_output --partial "Corrupted MEMORY.md"
  assert_output --partial "Rolled back"

  # MEMORY.md should now contain the backup content
  grep -q "Express" "$TEST_MEMORY_DIR/MEMORY.md"
  grep -q "Architecture" "$TEST_MEMORY_DIR/MEMORY.md"

  # The refusal text should be gone
  ! grep -q "I'm sorry" "$TEST_MEMORY_DIR/MEMORY.md"
}
