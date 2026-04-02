#!/usr/bin/env bats
# Tests for plugins/tandem/lib/tandem.sh shared library.

load '../helpers/test_helper'
load '../helpers/mock_claude'

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Source the library with required variables.
# Must be called inside each @test (not in setup) because TANDEM_LOG_LEVEL
# and .env loading happen at source time.
_source_lib() {
  export PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
  export _TANDEM_SCRIPT="test"
  source "$PLUGIN_ROOT/lib/tandem.sh"
}

# ─── Logging ──────────────────────────────────────────────────────────────────

@test "tandem_log writes correct format to log file" {
  _source_lib

  tandem_log info "hello world"

  [ -f "$HOME/.tandem/logs/tandem.log" ]
  local line
  line=$(cat "$HOME/.tandem/logs/tandem.log")

  # Format: YYYY-MM-DD HH:MM:SS [INFO ] [version] [test] hello world
  [[ "$line" == *"[INFO ]"* ]]
  local plugin_ver
  plugin_ver=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  [[ "$line" == *"[${plugin_ver}]"* ]]
  [[ "$line" == *"[test]"* ]]
  [[ "$line" == *"hello world"* ]]
}

@test "tandem_log respects TANDEM_LOG_LEVEL threshold" {
  export TANDEM_LOG_LEVEL="info"
  _source_lib

  tandem_log debug "should be skipped"

  if [ -f "$HOME/.tandem/logs/tandem.log" ]; then
    run cat "$HOME/.tandem/logs/tandem.log"
    refute_output --partial "should be skipped"
  fi
}

@test "tandem_log creates log directory if missing" {
  rm -rf "$HOME/.tandem/logs"
  _source_lib

  tandem_log info "create dirs"

  [ -d "$HOME/.tandem/logs" ]
  [ -f "$HOME/.tandem/logs/tandem.log" ]
}

@test "tandem_log format includes timestamp" {
  _source_lib

  tandem_log warn "timestamp check"

  local line
  line=$(cat "$HOME/.tandem/logs/tandem.log")

  # Timestamp format: YYYY-MM-DD HH:MM:SS
  local pattern='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] '
  [[ "$line" =~ $pattern ]]
}

# ─── Output ───────────────────────────────────────────────────────────────────

@test "tandem_print outputs logo with message" {
  _source_lib

  run tandem_print "hello there"

  assert_output "◎╵═╵◎ ~ hello there"
}

@test "tandem_header outputs version and stats from stats.json" {
  create_stats 42 7
  _source_lib

  run tandem_header

  local plugin_ver
  plugin_ver=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  assert_output "◎╵═╵◎ ~ Tandem v${plugin_ver} · ▷ 42 · ↻ 7"
}

@test "tandem_header handles missing stats.json with defaults" {
  rm -f "$HOME/.tandem/state/stats.json"
  _source_lib

  run tandem_header

  local plugin_ver
  plugin_ver=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  assert_output "◎╵═╵◎ ~ Tandem v${plugin_ver} · ▷ 0 · ↻ 0"
}

# ─── Dependencies ────────────────────────────────────────────────────────────

@test "tandem_require_jq exits 0 when jq is present" {
  _source_lib

  run tandem_require_jq

  assert_success
}

@test "tandem_require_claude returns 0 when present, 1 when missing" {
  _source_lib

  # claude is on PATH via mock
  run tandem_require_claude
  assert_success

  # Remove claude from PATH
  _remove_mock_claude
  run tandem_require_claude
  assert_failure
}

# ─── .env loading ────────────────────────────────────────────────────────────

@test "sources ~/.tandem/.env when it exists" {
  mkdir -p "$HOME/.tandem"
  echo 'TANDEM_TEST_SENTINEL="loaded_from_env"' > "$HOME/.tandem/.env"

  _source_lib

  [ "$TANDEM_TEST_SENTINEL" = "loaded_from_env" ]
}

@test "no error when .env does not exist" {
  rm -f "$HOME/.tandem/.env"

  run bash -c '
    export HOME="'"$HOME"'"
    export PLUGIN_ROOT="'"$CLAUDE_PLUGIN_ROOT"'"
    export _TANDEM_SCRIPT="test"
    source "$PLUGIN_ROOT/lib/tandem.sh"
    echo "ok"
  '

  assert_success
  assert_output "ok"
}

# ─── tandem_require_llm ──────────────────────────────────────────────────────

@test "tandem_require_llm: claude backend returns 0 when present" {
  _source_lib

  run tandem_require_llm

  assert_success
}

@test "tandem_require_llm: URL backend returns 1 when curl missing" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  export TANDEM_LLM_MODEL="llama3.2"
  _source_lib

  # Strip PATH to just mock_bin (has claude but not curl)
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  export PATH="$mock_dir"

  run tandem_require_llm

  assert_failure
}

@test "tandem_require_llm: URL backend returns 1 when TANDEM_LLM_MODEL not set" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  unset TANDEM_LLM_MODEL
  _source_lib

  run tandem_require_llm

  assert_failure
}

@test "tandem_require_llm: URL backend returns 0 when curl + jq + model present" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  export TANDEM_LLM_MODEL="llama3.2"
  _source_lib

  # curl and jq are on ORIGINAL_PATH; mock_bin prepended
  run tandem_require_llm

  assert_success
}

# ─── tandem_llm_call: claude backend ─────────────────────────────────────────

@test "tandem_llm_call: claude backend calls claude and returns output" {
  _install_mock_claude "extracted summary"
  _source_lib

  run tandem_llm_call "summarise this"

  assert_success
  assert_output "extracted summary"
}

@test "tandem_llm_call: claude backend returns 1 on empty response" {
  _install_mock_claude_fail empty
  _source_lib

  run tandem_llm_call "summarise this"

  assert_failure
}

@test "tandem_llm_call: claude backend returns 1 on Error: prefix response" {
  _install_mock_claude_fail error
  _source_lib

  run tandem_llm_call "summarise this"

  assert_failure
}

# ─── tandem_llm_call: URL backend ───────────────────────────────────────────

@test "tandem_llm_call: URL backend POSTs and returns parsed content" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  export TANDEM_LLM_MODEL="llama3.2"
  _install_mock_curl '{"choices":[{"message":{"content":"the response"}}]}'
  _source_lib

  run tandem_llm_call "hello"

  assert_success
  assert_output "the response"
}

@test "tandem_llm_call: URL backend includes Authorization header when API key set" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  export TANDEM_LLM_MODEL="llama3.2"
  export TANDEM_LLM_API_KEY="sk-test-key-123"

  # Custom curl mock that captures args and returns valid response
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/curl" <<'MOCK_EOF'
#!/bin/bash
echo "$@" > "$HOME/.tandem/state/curl_args.txt"
printf '%s' '{"choices":[{"message":{"content":"ok"}}]}'
MOCK_EOF
  chmod +x "$mock_dir/curl"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  _source_lib

  run tandem_llm_call "hello"

  assert_success
  local captured
  captured=$(cat "$HOME/.tandem/state/curl_args.txt")
  [[ "$captured" == *"Authorization: Bearer sk-test-key-123"* ]]
}

@test "tandem_llm_call: URL backend returns 1 on curl failure" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  export TANDEM_LLM_MODEL="llama3.2"
  _install_mock_curl_fail timeout
  _source_lib

  run tandem_llm_call "hello"

  assert_failure
}

@test "tandem_llm_call: URL backend returns 1 on API error response" {
  export TANDEM_LLM_BACKEND="http://localhost:11434"
  export TANDEM_LLM_MODEL="llama3.2"
  _install_mock_curl_fail api_error
  _source_lib

  run tandem_llm_call "hello"

  assert_failure
}

# ─── tandem_progress_dir ────────────────────────────────────────────────────

@test "tandem_progress_dir: returns git-root/.claude for git repos" {
  _source_lib
  init_test_git_repo
  local git_root
  git_root=$(git -C "$TEST_CWD" rev-parse --show-toplevel)

  run tandem_progress_dir "$TEST_CWD"

  assert_success
  assert_output "$git_root/.claude"
}

@test "tandem_progress_dir: returns fallback path for non-git directories" {
  _source_lib
  local non_git="$TEST_TEMP_DIR/not-a-repo"
  mkdir -p "$non_git"

  run tandem_progress_dir "$non_git"

  assert_success
  local expected_slug
  expected_slug=$(echo "$non_git" | sed 's|/|-|g')
  assert_output "$HOME/.tandem/progress/${expected_slug}"
}

# ─── tandem_memory_dir ──────────────────────────────────────────────────────

@test "tandem_memory_dir: returns CWD-based auto-memory path" {
  _source_lib

  run tandem_memory_dir "$TEST_CWD"

  assert_success
  local expected_slug
  expected_slug=$(echo "$TEST_CWD" | sed 's|/|-|g')
  assert_output "$HOME/.claude/projects/${expected_slug}/memory"
}

# ─── tandem_header with progress_dir ────────────────────────────────────────

@test "tandem_header: shows prog age when progress_dir has progress.md" {
  create_stats 10 2
  _source_lib
  echo "test" > "$TEST_PROGRESS_DIR/progress.md"

  run tandem_header "$TEST_MEMORY_DIR" "$TEST_PROGRESS_DIR"

  assert_success
  assert_output --partial "prog:<1m"
}

@test "tandem_header: shows prog:- when progress_dir has no progress.md" {
  create_stats 10 2
  _source_lib
  rm -f "$TEST_PROGRESS_DIR/progress.md"

  run tandem_header "$TEST_MEMORY_DIR" "$TEST_PROGRESS_DIR"

  assert_success
  assert_output --partial "prog:-"
}
