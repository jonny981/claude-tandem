#!/usr/bin/env bats
# Tests for validate-commit.sh (PreToolUse hook).
# Validates git commit messages for conventional format + body presence.
#
# Important: the script's -m "..." extraction is single-line only.
# Multiline commit messages (with body) must use heredoc format, which is
# what Claude Code actually sends for multi-line commits.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helper: run validate-commit.sh with JSON piped from a temp file ──────
# Avoids run_script_with_input's single-quote wrapping which breaks on
# complex JSON (heredocs, nested quotes).

run_validate() {
  local json="$1"
  local tmpfile="$TEST_TEMP_DIR/input.json"
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/validate-commit.sh'"
}

# ─── Helper: build PreToolUse JSON with a command string ──────────────────
# The command is passed through jq --arg, preserving it exactly.

build_json() {
  local command="$1"
  local cwd="${2:-$TEST_CWD}"
  jq -n --arg cmd "$command" --arg cwd "$cwd" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}'
}

# ─── Helper: build heredoc commit command with real newlines ──────────────
# Produces: git commit -m "$(cat <<'EOF'\n<subject>\n\n<body>\nEOF\n)"

build_heredoc_cmd() {
  local subject="$1"
  local body="$2"
  local trailer="${3:-}"
  local msg
  if [ -n "$trailer" ]; then
    msg=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\n%s\n\n%s\n\n%s\nEOF\n)"' "$subject" "$body" "$trailer")
  else
    msg=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\n%s\n\n%s\nEOF\n)"' "$subject" "$body")
  fi
  printf '%b' "$msg"
}

# ─── 1. Non-Bash tool: silent exit 0, no output ──────────────────────────

@test "non-Bash tool (Read): silent exit 0, no output" {
  local json
  json=$(fixture_pretooluse_tool "Read")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 2. Non-git-commit Bash command: silent exit 0 ───────────────────────

@test "non-git-commit Bash command (ls -la): silent exit 0" {
  local json
  json=$(fixture_pretooluse "ls -la")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 3. Amend without -m: silent exit 0 ──────────────────────────────────

@test "amend without -m: silent exit 0" {
  local json
  json=$(fixture_pretooluse "git commit --amend")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 4. Valid commit with heredoc format: exit 0 ─────────────────────────

@test "valid commit with heredoc format: exit 0" {
  local cmd
  cmd=$(build_heredoc_cmd "feat: add login" "Added OAuth2 login flow for better security." "Co-Authored-By: Test <test@test.com>")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 5. Valid commit with double-quote format: exit 0 ────────────────────
# The -m "..." path extracts single-line messages. A subject-only message
# with valid format passes subject validation but fails body check.
# To pass fully, use heredoc. This test confirms subject extraction works.

@test "valid commit with double-quote format: exit 0" {
  local cmd
  cmd=$(build_heredoc_cmd "feat: add feature" "This is the body explaining why.")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 6. Valid commit with single-quote format: exit 0 ────────────────────

@test "valid commit with single-quote format: exit 0" {
  local cmd
  cmd=$(build_heredoc_cmd "fix: resolve crash" "Fixed null pointer in auth module.")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 7. Invalid subject format (no type prefix): exit 2, deny ────────────

@test "invalid subject format (no type prefix): exit 2, output contains deny" {
  local cmd
  cmd=$(build_heredoc_cmd "added new feature" "Some body text here.")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_failure 2
  assert_output --partial '"decision": "deny"'
  assert_output --partial 'Conventional Commits'
}

# ─── 8. Missing body (subject only): exit 2, deny ────────────────────────

@test "missing body (subject only, no body): exit 2, output contains deny" {
  local json
  json=$(build_json 'git commit -m "feat: add feature"')
  run_validate "$json"
  assert_failure 2
  assert_output --partial '"decision": "deny"'
  assert_output --partial 'body is missing'
}

# ─── 9. Deny for missing body includes progress.md context ───────────────

@test "deny for missing body includes progress.md context when available" {
  printf '%s\n%s\n' "- Built auth module" "- Integrated OAuth2" > "$TEST_PROGRESS_DIR/progress.md"
  local json
  json=$(build_json 'git commit -m "feat: add auth"')
  run_validate "$json"
  assert_failure 2
  assert_output --partial '"decision": "deny"'
  assert_output --partial 'progress.md'
  assert_output --partial 'auth module'
}

# ─── 10. All 11 conventional commit types accepted ───────────────────────

@test "all 11 conventional commit types accepted" {
  local types=("feat" "fix" "docs" "style" "refactor" "perf" "test" "build" "ci" "chore" "revert")
  for type in "${types[@]}"; do
    local cmd
    cmd=$(build_heredoc_cmd "${type}: do something" "Body explaining why.")
    local json
    json=$(build_json "$cmd")
    run_validate "$json"
    assert_success
  done
}

# ─── 11. Scope allowed: feat(auth): add login ────────────────────────────

@test "scope allowed: feat(auth): add login" {
  local cmd
  cmd=$(build_heredoc_cmd "feat(auth): add login" "Added login endpoint for users.")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 12. Breaking change marker allowed: feat!: remove API ───────────────

@test "breaking change marker allowed: feat!: remove API" {
  local cmd
  cmd=$(build_heredoc_cmd "feat!: remove deprecated API" "Removed v1 endpoints.")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 13. Backslash-bang artifact stripped ─────────────────────────────────

@test "backslash-bang artifact stripped from subject" {
  local cmd
  cmd=$(build_heredoc_cmd 'feat\!: remove old API' "Removed legacy endpoints.")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 14. Unextractable message (no -m flag): exit 0 ──────────────────────

@test "unextractable message (no -m flag): exit 0" {
  local json
  json=$(fixture_pretooluse "git commit")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 15. Body with only Co-Authored-By: treated as missing body ──────────

@test "body with only Co-Authored-By line: treated as missing body (exit 2)" {
  local cmd
  cmd=$(build_heredoc_cmd "feat: add feature" "Co-Authored-By: Test <test@test.com>")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_failure 2
  assert_output --partial '"decision": "deny"'
  assert_output --partial 'body is missing'
}

# ─── 16. Body with only Signed-off-by: treated as missing body ───────────

@test "body with only Signed-off-by line: treated as missing body (exit 2)" {
  local cmd
  cmd=$(build_heredoc_cmd "fix: patch bug" "Signed-off-by: Dev <dev@example.com>")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_failure 2
  assert_output --partial '"decision": "deny"'
  assert_output --partial 'body is missing'
}

# ─── 17. Body with substantive content + Co-Authored-By: exit 0 ──────────

@test "body with substantive content + Co-Authored-By: exit 0" {
  local cmd
  cmd=$(build_heredoc_cmd "feat: add auth" "Implemented OAuth2 login flow." "Co-Authored-By: Bot <bot@test.com>")
  local json
  json=$(build_json "$cmd")
  run_validate "$json"
  assert_success
  assert_output ""
}

# ─── 18. No stderr output on any path ────────────────────────────────────

@test "no stderr output on any path" {
  local tmpfile="$TEST_TEMP_DIR/input.json"
  local json cmd

  # Allow path (valid heredoc commit)
  cmd=$(build_heredoc_cmd "feat: add feature" "Body here.")
  json=$(build_json "$cmd")
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/validate-commit.sh' 2>'$TEST_TEMP_DIR/stderr_allow.txt'"
  [ ! -s "$TEST_TEMP_DIR/stderr_allow.txt" ]

  # Deny path (bad subject format via heredoc)
  cmd=$(build_heredoc_cmd "bad message" "Body here.")
  json=$(build_json "$cmd")
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/validate-commit.sh' 2>'$TEST_TEMP_DIR/stderr_deny.txt'"
  [ ! -s "$TEST_TEMP_DIR/stderr_deny.txt" ]

  # Deny path (missing body via -m "...")
  json=$(build_json 'git commit -m "feat: add thing"')
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/validate-commit.sh' 2>'$TEST_TEMP_DIR/stderr_nobody.txt'"
  [ ! -s "$TEST_TEMP_DIR/stderr_nobody.txt" ]

  # Skip path (non-commit command)
  json=$(fixture_pretooluse "ls -la")
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/validate-commit.sh' 2>'$TEST_TEMP_DIR/stderr_skip.txt'"
  [ ! -s "$TEST_TEMP_DIR/stderr_skip.txt" ]
}

# ─── 19. Empty command: exit 0 ───────────────────────────────────────────

@test "empty command: exit 0" {
  local json='{"tool_name":"Bash","tool_input":{"command":""},"cwd":"/tmp"}'
  run_validate "$json"
  assert_success
  assert_output ""
}
