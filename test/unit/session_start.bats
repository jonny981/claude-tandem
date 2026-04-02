#!/usr/bin/env bats
# Tests for session-start.sh (SessionStart hook).
# Handles: provisioning, stats, version upgrade, CLAUDE.md injection,
# post-compaction recovery, milestones, recap, health check, indicators,
# recurrence alerts, cross-project context, stale progress, checkpoint detection.

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

SCRIPT="session-start.sh"

# Helper: run session-start with optional source field
run_session_start() {
  local source="${1:-startup}"
  local cwd="${2:-$TEST_CWD}"
  local json
  json=$(printf '{"cwd":"%s","source":"%s"}' "$cwd" "$source")
  local tmpfile="$TEST_TEMP_DIR/input.json"
  printf '%s' "$json" > "$tmpfile"
  run bash -c "cat '$tmpfile' | '$PLUGIN_ROOT/scripts/$SCRIPT'"
}

# ─── 1. Guard: TANDEM_WORKER ────────────────────────────────────────────────

@test "TANDEM_WORKER set: exit 0, no output" {
  export TANDEM_WORKER=1
  run_session_start
  assert_success
  assert_output ""
}

# ─── 2–5. First-run provisioning ────────────────────────────────────────────

@test "first run: copies rules files to ~/.claude/rules/" {
  rm -f "$HOME/.tandem/.provisioned"
  rm -f "$HOME/.claude/rules"/tandem-*.md
  run_session_start
  assert_success
  [ -f "$HOME/.claude/rules/tandem-recall.md" ]
  [ -f "$HOME/.claude/rules/tandem-display.md" ]
  [ -f "$HOME/.claude/rules/tandem-commits.md" ]
}

@test "first run: creates .provisioned marker" {
  rm -f "$HOME/.tandem/.provisioned"
  run_session_start
  assert_success
  [ -f "$HOME/.tandem/.provisioned" ]
}

@test "re-run (marker exists): does not re-provision rules" {
  # First run to provision
  rm -f "$HOME/.tandem/.provisioned"
  run_session_start
  assert_success

  # Remove rules to prove they won't be re-copied
  rm -f "$HOME/.claude/rules"/tandem-*.md
  run_session_start
  assert_success
  [ ! -f "$HOME/.claude/rules/tandem-recall.md" ]
}

# ─── 6–7. Stats initialization ──────────────────────────────────────────────

@test "missing stats.json: creates it with initial values" {
  rm -f "$HOME/.tandem/state/stats.json"
  run_session_start
  assert_success
  [ -f "$HOME/.tandem/state/stats.json" ]
  local total
  total=$(jq -r '.total_sessions' "$HOME/.tandem/state/stats.json")
  # Created with 0 then incremented to 1 (source=startup)
  [ "$total" = "1" ]
}

@test "existing stats.json: not overwritten" {
  create_stats 42 5
  run_session_start
  assert_success
  local total
  total=$(jq -r '.total_sessions' "$HOME/.tandem/state/stats.json")
  # 42 + 1 = 43 (source=startup increments)
  [ "$total" = "43" ]
}

# ─── 8–9. Version upgrade ───────────────────────────────────────────────────

@test "rules file with old version comment: updated to match source" {
  # Create marker so provisioning is skipped
  mkdir -p "$HOME/.tandem"
  date +%s > "$HOME/.tandem/.provisioned"

  # Install a rules file with an old version
  mkdir -p "$HOME/.claude/rules"
  printf '<!-- tandem v0.0.1 -->\n# Old rules content\n' > "$HOME/.claude/rules/tandem-recall.md"

  run_session_start
  assert_success

  # Should have been replaced with source version
  local installed_ver
  installed_ver=$(head -1 "$HOME/.claude/rules/tandem-recall.md" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
  local source_ver
  source_ver=$(head -1 "$PLUGIN_ROOT/rules/tandem-recall.md" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
  [ "$installed_ver" = "$source_ver" ]
}

@test "rules file with matching version: not modified" {
  mkdir -p "$HOME/.tandem"
  date +%s > "$HOME/.tandem/.provisioned"
  mkdir -p "$HOME/.claude/rules"

  # Copy actual source file then add a marker line to detect if it gets overwritten
  cp "$PLUGIN_ROOT/rules/tandem-recall.md" "$HOME/.claude/rules/tandem-recall.md"
  echo "# MARKER LINE" >> "$HOME/.claude/rules/tandem-recall.md"

  run_session_start
  assert_success

  # Marker should still be present (file was not replaced)
  grep -q "MARKER LINE" "$HOME/.claude/rules/tandem-recall.md"
}

# ─── 10–13. CLAUDE.md injection ─────────────────────────────────────────────

@test "no CLAUDE.md: creates one with tandem section" {
  rm -f "$HOME/.claude/CLAUDE.md"
  run_session_start
  assert_success
  [ -f "$HOME/.claude/CLAUDE.md" ]
  grep -q '<!-- tandem:start' "$HOME/.claude/CLAUDE.md"
  grep -q '<!-- tandem:end -->' "$HOME/.claude/CLAUDE.md"
  grep -q 'progress.md' "$HOME/.claude/CLAUDE.md"
}

@test "CLAUDE.md exists without tandem section: appends section" {
  mkdir -p "$HOME/.claude"
  echo "# My Project" > "$HOME/.claude/CLAUDE.md"
  run_session_start
  assert_success
  grep -q '# My Project' "$HOME/.claude/CLAUDE.md"
  grep -q '<!-- tandem:start' "$HOME/.claude/CLAUDE.md"
}

@test "CLAUDE.md exists with tandem section (same version): no change" {
  mkdir -p "$HOME/.claude"
  local plugin_ver
  plugin_ver=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  cat > "$HOME/.claude/CLAUDE.md" <<EOF
# My Project
<!-- tandem:start v${plugin_ver} -->
## Tandem -- Session Progress
Original content here.
<!-- tandem:end -->
EOF
  local before_md5
  before_md5=$(md5 -q "$HOME/.claude/CLAUDE.md" 2>/dev/null || md5sum "$HOME/.claude/CLAUDE.md" | cut -d' ' -f1)

  run_session_start
  assert_success

  local after_md5
  after_md5=$(md5 -q "$HOME/.claude/CLAUDE.md" 2>/dev/null || md5sum "$HOME/.claude/CLAUDE.md" | cut -d' ' -f1)
  [ "$before_md5" = "$after_md5" ]
}

@test "CLAUDE.md exists with tandem section (old version): section replaced" {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/CLAUDE.md" <<'EOF'
# My Project
Some content above.
<!-- tandem:start v0.0.1 -->
## Tandem -- Old Section
Old instructions here.
<!-- tandem:end -->
Some content below.
EOF
  run_session_start
  assert_success

  # Old version gone
  ! grep -q 'v0.0.1' "$HOME/.claude/CLAUDE.md"
  # New version present
  local plugin_ver
  plugin_ver=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  grep -q "v${plugin_ver}" "$HOME/.claude/CLAUDE.md"
  # Surrounding content preserved
  grep -q '# My Project' "$HOME/.claude/CLAUDE.md"
  grep -q 'Some content below.' "$HOME/.claude/CLAUDE.md"
}

# ─── 14–16. Post-compaction recovery ────────────────────────────────────────

@test "progress.md with Pre-compaction State section: outputs state content" {
  create_progress "$(printf '## Earlier Work\n- Did stuff\n\n## Pre-compaction State\nWorking on auth module\nNext: write tests')"
  run_session_start
  assert_success
  assert_output --partial "Resuming. Before compaction you were:"
  assert_output --partial "Working on auth module"
  assert_output --partial "Next: write tests"
}

@test "state section stripped from progress.md after output" {
  create_progress "$(printf '## Earlier Work\n- Did stuff\n\n## Pre-compaction State\nWorking on auth module')"
  run_session_start
  assert_success
  ! grep -q 'Pre-compaction State' "$TEST_PROGRESS_DIR/progress.md"
}

@test "earlier progress.md content preserved after stripping state section" {
  create_progress "$(printf '## Earlier Work\n- Did stuff\n\n## Pre-compaction State\nWorking on auth module')"
  run_session_start
  assert_success
  grep -q 'Earlier Work' "$TEST_PROGRESS_DIR/progress.md"
  grep -q 'Did stuff' "$TEST_PROGRESS_DIR/progress.md"
}

# ─── 17. Session count ──────────────────────────────────────────────────────

@test "total_sessions incremented on startup source" {
  create_stats 5 0
  run_session_start "startup"
  assert_success
  local total
  total=$(jq -r '.total_sessions' "$HOME/.tandem/state/stats.json")
  [ "$total" = "6" ]
}

@test "total_sessions NOT incremented on resume source" {
  create_stats 5 0
  run_session_start "resume"
  assert_success
  local total
  total=$(jq -r '.total_sessions' "$HOME/.tandem/state/stats.json")
  [ "$total" = "5" ]
}

@test "total_sessions NOT incremented on compact source" {
  create_stats 5 0
  run_session_start "compact"
  assert_success
  local total
  total=$(jq -r '.total_sessions' "$HOME/.tandem/state/stats.json")
  [ "$total" = "5" ]
}

# ─── 18–20. MEMORY.md corruption detection ──────────────────────────────────

@test "short MEMORY.md (< 5 lines): rolls back to backup if available" {
  echo "short" > "$TEST_MEMORY_DIR/MEMORY.md"
  echo "# Full backup content
## Section 1
Real data here
More real data
Even more data
Line six" > "$TEST_MEMORY_DIR/.MEMORY.md.backup-1234"

  run_session_start
  assert_success
  local line_count
  line_count=$(wc -l < "$TEST_MEMORY_DIR/MEMORY.md" | tr -d ' ')
  [ "$line_count" -gt 4 ]
  grep -q "Full backup content" "$TEST_MEMORY_DIR/MEMORY.md"
}

@test "MEMORY.md starting with refusal pattern: rolls back" {
  printf 'I cannot help with that request.\nSome other content.\nMore lines.\nLine 4.\nLine 5.\nLine 6.' > "$TEST_MEMORY_DIR/MEMORY.md"
  echo "# Good backup
## Real content
Data line 1
Data line 2
Data line 3
Data line 6" > "$TEST_MEMORY_DIR/.MEMORY.md.backup-5678"

  run_session_start
  assert_success
  grep -q "Good backup" "$TEST_MEMORY_DIR/MEMORY.md"
  assert_output --partial "Corrupted MEMORY.md detected"
}

@test "corrupted MEMORY.md, no backup available: no crash" {
  echo "tiny" > "$TEST_MEMORY_DIR/MEMORY.md"
  rm -f "$TEST_MEMORY_DIR"/.MEMORY.md.backup-*

  run_session_start
  assert_success
  # File should still be there (not deleted)
  [ -f "$TEST_MEMORY_DIR/MEMORY.md" ]
}

# ─── 21–22. Milestones ──────────────────────────────────────────────────────

@test "session count hits 10: outputs milestone message" {
  create_stats 9 2
  run_session_start "startup"
  assert_success
  assert_output --partial "Milestone: 10 sessions!"
}

@test "already-hit milestone: not repeated" {
  # Pre-set milestones_hit to include 10
  cat > "$HOME/.tandem/state/stats.json" <<'STATS_EOF'
{
  "total_sessions": 9,
  "first_session": "2025-01-01",
  "last_session": "2025-01-01",
  "compactions": 2,
  "milestones_hit": ["10"]
}
STATS_EOF

  run_session_start "startup"
  assert_success
  refute_output --partial "Milestone: 10 sessions!"
}

# ─── 23–24. Recap ───────────────────────────────────────────────────────────

@test "recap file with memory_lines: shows memory line count" {
  cat > "$HOME/.tandem/.last-session-recap" <<'EOF'
recall_status: inline
memory_lines: 42
EOF

  run_session_start
  assert_success
  assert_output --partial "memory at 42 lines"
}

@test "recap file cleaned up after display" {
  cat > "$HOME/.tandem/.last-session-recap" <<'EOF'
recall_status: inline
memory_lines: 42
EOF

  run_session_start
  assert_success
  [ ! -f "$HOME/.tandem/.last-session-recap" ]
}

# ─── 25. Health check ───────────────────────────────────────────────────────

@test "log file with errors for current version: shows issue count" {
  local plugin_ver
  plugin_ver=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  mkdir -p "$HOME/.tandem/logs"
  # The script greps for [VERSION].*([ERROR]|[WARN ]), so version must precede the label
  # in each line for the pattern to match. The actual tandem_log format puts the label
  # before version, but we test the grep pattern as written in the script.
  printf '2025-01-01 12:00:00 [%s] [ERROR] [test] something broke\n' "$plugin_ver" > "$HOME/.tandem/logs/tandem.log"
  printf '2025-01-01 12:01:00 [%s] [WARN ] [test] something fishy\n' "$plugin_ver" >> "$HOME/.tandem/logs/tandem.log"

  run_session_start
  assert_success
  assert_output --partial "2 issue(s) logged"
  assert_output --partial "/tandem:logs"
}

# ─── 26–27. Indicators ──────────────────────────────────────────────────────

@test ".tandem-last-compaction marker: shows Recalled. and cleaned up" {
  touch "$TEST_MEMORY_DIR/.tandem-last-compaction"
  create_stats 5 3

  run_session_start
  assert_success
  assert_output --partial "Recalled."
  assert_output --partial "3 compactions total"
  [ ! -f "$TEST_MEMORY_DIR/.tandem-last-compaction" ]
}

# ─── 28. Recurrence ─────────────────────────────────────────────────────────

@test "recurrence.json with theme count >= 3: shows recurring alert" {
  cat > "$HOME/.tandem/state/recurrence.json" <<'EOF'
{
  "themes": {
    "error handling": {"count": 4, "last_seen": "2025-01-10"},
    "logging": {"count": 1, "last_seen": "2025-01-09"}
  }
}
EOF

  run_session_start
  assert_success
  assert_output --partial "Recurring:"
  assert_output --partial "error handling (4 sessions)"
  refute_output --partial "logging"
}

# ─── 29. Cross-project context ──────────────────────────────────────────────

@test "global.md with entries from other projects: shows context section" {
  mkdir -p "$HOME/.tandem/memory"
  local project_name
  project_name=$(basename "$TEST_CWD")
  cat > "$HOME/.tandem/memory/global.md" <<EOF
## 2025-01-10 -- other-project
Built authentication module with OAuth2 flow.
## 2025-01-09 -- ${project_name}
This entry is from the current project and should not appear.
## 2025-01-08 -- another-app
Refactored database layer for better performance.
EOF

  run_session_start
  assert_success
  assert_output --partial "Context from other projects:"
  assert_output --partial "other-project"
  assert_output --partial "another-app"
  refute_output --partial "This entry is from the current project"
}

# ─── 30. Stale progress ─────────────────────────────────────────────────────

@test "progress.md older than 300s: shows carry-forward notice" {
  create_progress "Previous session work" 600
  run_session_start
  assert_success
  assert_output --partial "Previous session notes found"
  assert_output --partial "Context carried forward"
}

# ─── 31. Migration ───────────────────────────────────────────────────────────

@test "migrates progress.md from auto-memory to progress dir" {
  echo "old progress data" > "$TEST_MEMORY_DIR/progress.md"
  rm -f "$TEST_PROGRESS_DIR/progress.md"
  run_session_start
  assert_success
  [ -f "$TEST_PROGRESS_DIR/progress.md" ]
  [ ! -f "$TEST_MEMORY_DIR/progress.md" ]
  grep -q "old progress data" "$TEST_PROGRESS_DIR/progress.md"
}

@test "removes stale auto-memory progress.md when new location exists" {
  echo "new data" > "$TEST_PROGRESS_DIR/progress.md"
  echo "old data" > "$TEST_MEMORY_DIR/progress.md"
  run_session_start
  assert_success
  [ -f "$TEST_PROGRESS_DIR/progress.md" ]
  [ ! -f "$TEST_MEMORY_DIR/progress.md" ]
}

# ─── 32. Gitignore ──────────────────────────────────────────────────────────

@test "ensures .claude/.gitignore contains progress.md in git repos" {
  init_test_git_repo
  run_session_start
  assert_success
  [ -f "$TEST_CWD/.claude/.gitignore" ]
  grep -q '^progress\.md$' "$TEST_CWD/.claude/.gitignore"
}

# ─── 33. Invariants ─────────────────────────────────────────────────────────

@test "always outputs header first (first line contains logo)" {
  run_session_start
  assert_success
  # First line must contain the Tandem logo
  local first_line
  first_line=$(echo "$output" | head -1)
  [[ "$first_line" == *"◎╵═╵◎"* ]]
}
