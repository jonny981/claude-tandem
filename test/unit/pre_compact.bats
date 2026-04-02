#!/usr/bin/env bats
# Tests for plugins/tandem/scripts/pre-compact.sh

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Create a minimal transcript file with real JSONL content
_create_transcript() {
  local path="${1:-$TEST_TEMP_DIR/transcript.jsonl}"
  echo '{"type":"message","content":"hello"}' > "$path"
  echo '{"type":"message","content":"working on auth module"}' >> "$path"
  echo "$path"
}

# ─── Early exits ─────────────────────────────────────────────────────────────

@test "TANDEM_WORKER set: exit 0, no output" {
  export TANDEM_WORKER=1
  local transcript
  transcript=$(_create_transcript)

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  assert_output ""
}

@test "empty CWD: exit 0" {
  local transcript
  transcript=$(_create_transcript)

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "" "$transcript")"

  assert_success
  assert_output ""
}

@test "empty transcript_path: exit 0" {
  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "")"

  assert_success
  assert_output ""
}

@test "non-existent transcript file: exit 0" {
  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "/tmp/does-not-exist-ever.jsonl")"

  assert_success
  assert_output ""
}

# ─── LLM failure modes ──────────────────────────────────────────────────────

@test "LLM missing (tandem_require_llm fails): exit 0" {
  local transcript
  transcript=$(_create_transcript)

  # Remove claude mock but keep system binaries on PATH
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  rm -f "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  assert_output ""
}

@test "LLM returns empty: exit 0, nothing written" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "existing content"
  _install_mock_claude_fail empty

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  assert_output ""
  # progress.md should be untouched
  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output "existing content"
}

@test "LLM returns SKIP: nothing appended to progress.md" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "existing content"
  _install_mock_claude_fixture "precompact-skip.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  # progress.md unchanged
  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output "existing content"
}

# ─── Fresh progress: state only ─────────────────────────────────────────────

@test "fresh progress + state-only response: only Pre-compaction State appended" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "existing notes" 0
  _install_mock_claude_fixture "precompact-state-only.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  # Should contain state section
  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output --partial "## Pre-compaction State"
  assert_output --partial "Working on user authentication module"
  # Should NOT contain progress section
  refute_output --partial "## Auto-captured (pre-compaction)"
}

@test "fresh progress: existing content preserved" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "first line of existing notes" 0
  _install_mock_claude_fixture "precompact-state-only.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output --partial "first line of existing notes"
  assert_output --partial "## Pre-compaction State"
}

# ─── Stale progress: state + progress ───────────────────────────────────────

@test "stale progress + state-and-progress response: both sections appended" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "old notes" 300
  _install_mock_claude_fixture "precompact-state-and-progress.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output --partial "## Pre-compaction State"
  assert_output --partial "## Auto-captured (pre-compaction)"
  assert_output --partial "Working on user authentication module"
  assert_output --partial "Implemented JWT token generation"
}

@test "stale progress: existing content preserved" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "pre-existing work log" 300
  _install_mock_claude_fixture "precompact-state-and-progress.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output --partial "pre-existing work log"
}

# ─── Missing progress.md ────────────────────────────────────────────────────

@test "missing progress.md: file created with both sections" {
  local transcript
  transcript=$(_create_transcript)
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  _install_mock_claude_fixture "precompact-state-and-progress.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  [ -f "$TEST_PROGRESS_DIR/progress.md" ]
  run cat "$TEST_PROGRESS_DIR/progress.md"
  assert_output --partial "## Pre-compaction State"
  assert_output --partial "## Auto-captured (pre-compaction)"
}

# ─── Section headers ────────────────────────────────────────────────────────

@test "STATE section header is '## Pre-compaction State'" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "" 0
  _install_mock_claude_fixture "precompact-state-only.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  run grep -c "## Pre-compaction State" "$TEST_PROGRESS_DIR/progress.md"
  assert_output "1"
}

@test "PROGRESS section header is '## Auto-captured (pre-compaction)'" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "" 300
  _install_mock_claude_fixture "precompact-state-and-progress.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  run grep -c "## Auto-captured (pre-compaction)" "$TEST_PROGRESS_DIR/progress.md"
  assert_output "1"
}

# ─── Output discipline ──────────────────────────────────────────────────────

@test "no stdout output on success" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "notes" 300
  _install_mock_claude_fixture "precompact-state-and-progress.txt"

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
  assert_output ""
}

@test "no stderr output on success" {
  local transcript
  transcript=$(_create_transcript)
  create_progress "notes" 300
  _install_mock_claude_fixture "precompact-state-and-progress.txt"

  run bash -c "echo '$(fixture_precompact "$TEST_CWD" "$transcript")' | '$PLUGIN_ROOT/scripts/pre-compact.sh' 2>$TEST_TEMP_DIR/stderr.txt"

  local stderr_content
  stderr_content=$(cat "$TEST_TEMP_DIR/stderr.txt")
  [ -z "$stderr_content" ]
}

# ─── Exit code discipline ───────────────────────────────────────────────────

@test "exit 0 on all paths: worker guard" {
  export TANDEM_WORKER=1
  run_script_with_input "pre-compact.sh" "{}"
  assert_success
}

@test "exit 0 on all paths: LLM failure" {
  local transcript
  transcript=$(_create_transcript)
  _install_mock_claude_fail exit

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success
}

# ─── Transcript reading ─────────────────────────────────────────────────────

@test "transcript tail is read from actual file" {
  # Create a transcript with identifiable content
  local transcript="$TEST_TEMP_DIR/real-transcript.jsonl"
  echo '{"type":"assistant","content":"Starting auth implementation"}' > "$transcript"
  echo '{"type":"user","content":"Add JWT support"}' >> "$transcript"

  # Use a mock that echoes the prompt it receives so we can verify transcript content was included
  local mock_dir="$TEST_TEMP_DIR/mock_bin"
  mkdir -p "$mock_dir"
  cat > "$mock_dir/claude" <<'MOCK_EOF'
#!/bin/bash
# Read stdin (the prompt) and save it, then return state-only response
STDIN=$(cat)
echo "$STDIN" > "$HOME/.tandem/state/captured_prompt.txt"
printf 'STATE:\n- Working on JWT implementation\n- User requested JWT support'
MOCK_EOF
  chmod +x "$mock_dir/claude"
  export PATH="$mock_dir:$ORIGINAL_PATH"

  create_progress "notes" 0

  run_script_with_input "pre-compact.sh" "$(fixture_precompact "$TEST_CWD" "$transcript")"

  assert_success

  # The prompt sent to claude should contain transcript content
  local captured
  captured=$(cat "$HOME/.tandem/state/captured_prompt.txt")
  [[ "$captured" == *"Add JWT support"* ]]
}
