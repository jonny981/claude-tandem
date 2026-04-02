#!/usr/bin/env bats
# Tests for guard-progress.sh (PreToolUse blocker for template-only progress.md).

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="guard-progress.sh"

# ─── Guard: TANDEM_WORKER ────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exits 0 with no output" {
  export TANDEM_WORKER=1
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/test/file.txt")"
  assert_success
  assert_output ""
}

# ─── Guard: empty CWD ────────────────────────────────────────────────────────

@test "empty CWD: exits 0 with no output" {
  run_script_with_input "$SCRIPT" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"cwd":""}'
  assert_success
  assert_output ""
}

# ─── Allow: writing TO progress.md ───────────────────────────────────────────

@test "writing to progress.md: always allowed even when template-only" {
  cat > "$TEST_PROGRESS_DIR/progress.md" <<'EOF'
**Current task:** [what you're actively doing]
EOF
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "$TEST_PROGRESS_DIR/progress.md")"
  assert_success
  assert_output ""
}

# ─── Block: missing progress.md ──────────────────────────────────────────────

@test "missing progress.md: blocks Write with reason" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/some/code.py")"
  assert_failure
  assert_output --partial '"decision"'
  assert_output --partial '"block"'
  assert_output --partial 'does not exist'
}

@test "missing progress.md: blocks Edit with reason" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_edit "/tmp/some/code.py")"
  assert_failure
  assert_output --partial '"block"'
}

# ─── Block: template-only progress.md ────────────────────────────────────────

@test "template-only progress.md: blocks Write with reason" {
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
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/some/code.py")"
  assert_failure
  assert_output --partial '"block"'
  assert_output --partial 'blank template'
}

# ─── Allow: populated progress.md ────────────────────────────────────────────

@test "populated progress.md: allows Write" {
  create_progress "## Working State
**Current task:** implementing auth
**Approach:** OAuth2 flow" 0
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/some/code.py")"
  assert_success
  assert_output ""
}

@test "populated progress.md: allows Edit" {
  create_progress "## Working State
**Current task:** implementing auth
**Approach:** OAuth2 flow" 0
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_edit "/tmp/some/code.py")"
  assert_success
  assert_output ""
}

# ─── Output format ───────────────────────────────────────────────────────────

@test "block output is valid JSON" {
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/some/code.py")"
  assert_failure
  echo "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

# ─── Exit codes ──────────────────────────────────────────────────────────────

@test "exits 0 when allowed, 2 when blocked" {
  # Allowed: populated progress
  create_progress "real content" 0
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/x")"
  assert_success

  # Blocked: missing progress
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_script_with_input "$SCRIPT" "$(fixture_pretooluse_write "/tmp/x")"
  [ "$status" -eq 2 ]
}
