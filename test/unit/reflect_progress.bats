#!/usr/bin/env bats
# Tests for reflect-progress.sh (Stop hook: reflection prompt for progress.md).
# Creates progress.md if missing. Prompts reflection on end_turn stops.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="reflect-progress.sh"

# ─── Guard: TANDEM_WORKER ────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exits 0 with no output" {
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  assert_output ""
}

# ─── Guard: empty CWD ───────────────────────────────────────────────────────���

@test "empty CWD: exits 0 with no output" {
  run_script_with_input "$SCRIPT" '{"cwd":"","stop_reason":"end_turn"}'
  assert_success
  assert_output ""
}

# ─── Guard: non-end_turn stop reason ──────────────────────────────────────────

@test "tool_use stop reason: no output" {
  create_progress "real content" 0
  run_script_with_input "$SCRIPT" "$(fixture_stop "$TEST_CWD" "tool_use")"
  assert_success
  assert_output ""
}

@test "empty stop reason: no output" {
  create_progress "real content" 0
  run_script_with_input "$SCRIPT" "$(fixture_stop "$TEST_CWD" "")"
  assert_success
  assert_output ""
}

# ─── Creates progress.md if missing ──────────────────────────────────────────

@test "missing progress.md: creates file with frontmatter" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  [ -f "$TEST_PROGRESS_DIR/progress.md" ]
  grep -q 'type: session-progress' "$TEST_PROGRESS_DIR/progress.md"
}

# ─── Reflection prompt ──────────────────────────────────────────────────────

@test "end_turn: outputs reflection prompt" {
  create_progress "Chose OAuth2 flow because the OEM API requires it" 0
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'Reflect'
}

@test "same reflection prompt regardless of progress content" {
  # Empty progress
  create_empty_progress
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  assert_output --partial 'Reflect'

  # Populated progress
  create_progress "some decisions captured" 0
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  assert_output --partial 'Reflect'
}

# ─── Output format ───────────────────────────────────────────────────────────

@test "output is valid JSON" {
  create_progress "real content" 0
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

# ─── Exit codes ──────────────────────────────────────────────────────────────

@test "exits 0 on all paths" {
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success
  unset TANDEM_WORKER

  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success

  create_progress "real content" 0
  run_script_with_input "$SCRIPT" "$(fixture_stop)"
  assert_success

  run_script_with_input "$SCRIPT" "$(fixture_stop "$TEST_CWD" "tool_use")"
  assert_success
}
