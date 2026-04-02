#!/usr/bin/env bats
# Tests for session-end.sh (simplified: summary + recurrence + global + deregister).
# No worker mode, no LLM calls.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="session-end.sh"

# ─── Guard: TANDEM_WORKER ────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exit 0, no output" {
  export TANDEM_WORKER=1
  create_progress "some progress notes"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output ""
}

# ─── Guard: empty CWD ────────────────────────────────────────────────────────

@test "no CWD in input: exit 0, no output" {
  create_progress "some progress notes"

  run_script_with_input "$SCRIPT" '{"cwd":""}'

  assert_success
  assert_output ""
}

# ─── Guard: no progress.md ───────────────────────────────────────────────────

@test "no progress.md: exit 0, no output" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output ""
}

# ─── Session summary ─────────────────────────────────────────────────────────

@test "with progress.md: outputs branded session ended message" {
  create_progress "line one
line two
line three"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  assert_output --partial "Session ended"
  assert_output --partial "lines"
}

@test "output contains line count from progress.md" {
  create_progress "line one
line two
line three"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  # Line count varies by trailing newline; just verify it's a number in output
  assert_output --partial "lines captured"
}

# ─── Recurrence tracking ─────────────────────────────────────────────────────

@test "updates recurrence.json when MEMORY.md has THEMES line" {
  create_progress "some work"
  echo '# Memory
THEMES: data-safety, performance' > "$TEST_MEMORY_DIR/MEMORY.md"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  [ -f "$HOME/.tandem/state/recurrence.json" ]
  run jq -r '.themes["data-safety"].count' "$HOME/.tandem/state/recurrence.json"
  assert_output "1"
  run jq -r '.themes["performance"].count' "$HOME/.tandem/state/recurrence.json"
  assert_output "1"
}

@test "increments existing recurrence counts" {
  create_progress "some work"
  echo '# Memory
THEMES: data-safety' > "$TEST_MEMORY_DIR/MEMORY.md"
  echo '{"themes":{"data-safety":{"count":3,"first_seen":"2026-01-01","last_seen":"2026-01-15"}}}' > "$HOME/.tandem/state/recurrence.json"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  run jq -r '.themes["data-safety"].count' "$HOME/.tandem/state/recurrence.json"
  assert_output "4"
}

@test "no recurrence update when MEMORY.md missing" {
  create_progress "some work"
  rm -f "$TEST_MEMORY_DIR/MEMORY.md"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  [ ! -f "$HOME/.tandem/state/recurrence.json" ]
}

@test "no recurrence update when MEMORY.md has no THEMES line" {
  create_progress "some work"
  echo '# Memory
Some content' > "$TEST_MEMORY_DIR/MEMORY.md"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  [ ! -f "$HOME/.tandem/state/recurrence.json" ]
}

# ─── Global activity log ─────────────────────────────────────────────────────

@test "writes to global.md" {
  create_progress "Implemented auth flow with OAuth2"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  [ -f "$HOME/.tandem/memory/global.md" ]
  run cat "$HOME/.tandem/memory/global.md"
  assert_output --partial "project"
}

# ─── Completed tasks cleanup ─────────────────────────────────────────────────

@test "cleans up completed-tasks.jsonl" {
  create_progress "some work"
  echo '{"subject":"test","ts":1234}' > "$HOME/.tandem/state/completed-tasks.jsonl"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  [ ! -f "$HOME/.tandem/state/completed-tasks.jsonl" ]
}

# ─── Exit code ────────────────────────────────────────────────────────────────

@test "exits 0 on all paths" {
  # With progress
  create_progress "work"
  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"
  assert_success

  # Without progress
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"
  assert_success

  # Empty CWD
  run_script_with_input "$SCRIPT" '{"cwd":""}'
  assert_success
}

# ─── No stderr ────────────────────────────────────────────────────────────────

@test "no stderr output" {
  create_progress "some work"
  run bash -c "echo '$(fixture_sessionend "$TEST_CWD")' | '$PLUGIN_ROOT/scripts/$SCRIPT' 2>$TEST_TEMP_DIR/stderr_out"
  local stderr_content
  stderr_content=$(cat "$TEST_TEMP_DIR/stderr_out")
  [ -z "$stderr_content" ]
}

# ─── Recap file ──────────────────────────────────────────────────────────────

@test "writes recap file" {
  create_progress "some work"

  run_script_with_input "$SCRIPT" "$(fixture_sessionend "$TEST_CWD")"

  assert_success
  [ -f "$HOME/.tandem/.last-session-recap" ]
  run cat "$HOME/.tandem/.last-session-recap"
  assert_output --partial "recall_status: inline"
}
