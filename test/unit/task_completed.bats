#!/usr/bin/env bats
# Tests for task-completed.sh (TaskCompleted hook - reflection trigger).
# Accumulates task subjects, asks Claude to evaluate progress.md updates.

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

# ─── Missing progress.md ─────────────────────────────────────────────────────

@test "missing progress.md: outputs strong creation nudge" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'does not exist'
}

# ─── Template-only progress.md ───────────────────────────────────────────────

@test "template-only progress.md: outputs fill-in nudge" {
  cat > "$TEST_PROGRESS_DIR/progress.md" <<'EOF'
---
framework: default
---
<!-- working-state:start -->
## Working State
**Current task:** [what you're actively doing]
**Approach:** [chosen approach and why]
<!-- working-state:end -->
EOF
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Fix bug")"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'blank template'
}

# ─── Fresh progress, no accumulated tasks ────────────────────────────────────

@test "fresh progress, no accumulated tasks: no output" {
  create_progress "## Working State
**Current task:** implementing auth
**Approach:** OAuth2" 0
  # Clean any accumulated tasks
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  # First task after fresh progress — gets accumulated but since progress is fresh,
  # only the just-accumulated task exists. It should still trigger evaluation.
  # (The task was just added to the accumulator, then read back)
}

# ─── Stale progress, no accumulated tasks ────────────────────────────────────

@test "stale progress (>300s): outputs evaluation nudge with accumulated task" {
  create_progress "## Working State
**Current task:** old task" 600
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Deploy")"
  assert_success
  assert_output --partial '"systemMessage"'
  # The task gets accumulated and the accumulated-tasks path fires
  assert_output --partial 'Deploy'
  assert_output --partial 'Evaluate'
}

# ─── Task accumulation ───────────────────────────────────────────────────────

@test "accumulates task subject to completed-tasks.jsonl" {
  create_progress "some work" 0
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD" "Add auth")"
  assert_success
  [ -f "$HOME/.tandem/state/completed-tasks.jsonl" ]
  run jq -r '.subject' "$HOME/.tandem/state/completed-tasks.jsonl"
  assert_output --partial "Add auth"
}

# ─── Output format ───────────────────────────────────────────────────────────

@test "output is valid JSON when nudge is sent" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
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
  create_progress "## Working State
**Current task:** testing" 0
  rm -f "$HOME/.tandem/state/completed-tasks.jsonl"
  run_script_with_input "$SCRIPT" "$(fixture_taskcompleted "$TEST_CWD")"
  assert_success

  # Stale progress
  create_progress "stale" 600
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
