#!/usr/bin/env bats
# Tests for check-progress.sh (UserPromptSubmit status line).
# Outputs status with file ages. No nudging — reflection is the Stop hook's job.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="check-progress.sh"

# ─── Guard: TANDEM_WORKER ────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exits 0 with no output" {
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "do something")"
  assert_success
  assert_output ""
}

# ─── Guard: empty CWD ────────────────────────────────────────────────────────

@test "empty CWD: exits 0 with no output" {
  run_script_with_input "$SCRIPT" '{"cwd":""}'
  assert_success
  assert_output ""
}

# ─── Status line ─────────────────────────────────────────────────────────────

@test "outputs status line with project, ages, and mod count" {
  create_progress "## Working State
**Current task:** implementing auth
**Approach:** OAuth2 flow" 0
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "continue")"
  assert_success
  assert_output --partial '"systemMessage"'
  assert_output --partial 'mem:'
  assert_output --partial 'prog:'
  assert_output --partial 'mod:'
}

@test "missing progress.md: status line shows prog:- (no nudge)" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "fix the bug")"
  assert_success
  assert_output --partial 'prog:-'
  refute_output --partial 'PREREQUISITE'
  # Should NOT create the file
  [ ! -f "$TEST_PROGRESS_DIR/progress.md" ]
}

@test "template-only progress.md: status line only (no nudge)" {
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
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "add feature")"
  assert_success
  assert_output --partial '"systemMessage"'
  refute_output --partial 'PREREQUISITE'
  refute_output --partial 'blank template'
}

# ─── Output format ───────────────────────────────────────────────────────────

@test "output is valid JSON" {
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "test")"
  assert_success
  echo "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

# ─── Exit code ────────────────────────────────────────────────────────────────

@test "exits 0 on all paths" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "test")"
  assert_success

  create_progress "real content" 0
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "test")"
  assert_success

  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_userpromptsubmit "test")"
  assert_success
}

# ─── No stderr ────────────────────────────────────────────────────────────────

@test "no stderr output" {
  run bash -c "echo '$(fixture_userpromptsubmit "hello")' | '$PLUGIN_ROOT/scripts/$SCRIPT' 2>$TEST_TEMP_DIR/stderr_out"
  local stderr_content
  stderr_content=$(cat "$TEST_TEMP_DIR/stderr_out")
  [ -z "$stderr_content" ]
}
