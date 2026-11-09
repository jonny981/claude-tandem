#!/usr/bin/env bats
# Tests for task-completed.sh (TaskCompleted hook - reflection trigger).
# Accumulates task subjects, nudges reflection based on accumulated work.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="task-completed.sh"

# ─── Guard: TANDEM_WORKER ────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exits 0 with no output" {
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  assert_output ""
}

# ─── Guard: empty CWD ────────────────────────────────────────────────────────

@test "empty CWD: exits 0 with no output" {
  run_script_with_input "$SCRIPT" '{"cwd":""}'
  assert_success
  assert_output ""
}

# ─── Missing progress.md: creates silently ───────────────────────────────────

@test "missing progress.md: creates file silently" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  [ -f "$TEST_PROGRESS_DIR/progress.md" ]
  grep -q 'type: session-progress' "$TEST_PROGRESS_DIR/progress.md"
}

# ─── Fresh progress, no accumulated tasks ────────────────────────────────────

@test "fresh progress, no accumulated tasks: no output" {
  create_progress "Investigating auth flow, chose OAuth2" 0
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
}

# ─── Stale progress: reflection nudge ────────────────────────────────────────

@test "stale progress (>300s): outputs reflection nudge" {
  create_progress "Started investigating auth" 600
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Deploy")"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'Reflect'
}

# ─── Task accumulation ───────────────────────────────────────────────────────

@test "accumulates task subject to completed-tasks.jsonl" {
  create_progress "some reasoning captured" 0
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  [ -f "$HOME/.tandem/state/completed-tasks.jsonl" ]
  run jq -r '.subject' "$HOME/.tandem/state/completed-tasks.jsonl"
  assert_output --partial "Add auth"
}

# ─── Output format ───────────────────────────────────────────────────────────

@test "output is valid JSON when nudge is sent" {
  create_progress "old reasoning" 600
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Deploy")"
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

# ─── Exit code ────────────────────────────────────────────────────────────────

@test "exits 0 on all paths" {
  # Missing progress
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Fresh progress
  create_progress "reasoning about auth" 0
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Stale progress
  create_progress "old reasoning" 600
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Empty CWD
  run_script_with_input "$SCRIPT" '{"cwd":""}'
  assert_success

  # Worker guard
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
}

# ─── No stderr ────────────────────────────────────────────────────────────────

@test "no stderr output" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run bash -c "echo '$(fixture_taskcompleted "$TEST_CWD" "Test")' | '$PLUGIN_ROOT/scripts/$SCRIPT' 2>$TEST_TEMP_DIR/stderr_out"
  local stderr_content
  stderr_content=$(cat "$TEST_TEMP_DIR/stderr_out")
  [ -z "$stderr_content" ]
}
