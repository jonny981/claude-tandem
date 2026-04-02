#!/usr/bin/env bats
# Integration: first installation journey
# Tests the complete first-run provisioning flow of session-start.sh

load '../helpers/test_helper'
load '../helpers/mock_claude'
load '../helpers/fixtures'

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Run session-start with a fully clean HOME (no marker, no stats, no rules)
_clean_session_start() {
  # Remove marker and stats that setup() may have created dirs for
  rm -f "$HOME/.tandem/.provisioned"
  rm -f "$HOME/.tandem/state/stats.json"
  rm -rf "$HOME/.claude/rules/tandem-"*
  rm -f "$HOME/.claude/CLAUDE.md"
  # Create a minimal settings.json so the hook doesn't error on jq parse
  mkdir -p "$HOME/.claude"
  echo '{}' > "$HOME/.claude/settings.json"
}

# ─── Tests ────────────────────────────────────────────────────────────────────

@test "first run: session-start provisions rules, stats, and CLAUDE.md" {
  _clean_session_start

  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"

  assert_success

  # Rules files provisioned
  [ -f "$HOME/.claude/rules/tandem-recall.md" ]
  [ -f "$HOME/.claude/rules/tandem-display.md" ]
  [ -f "$HOME/.claude/rules/tandem-commits.md" ]

  # Stats file initialised
  [ -f "$HOME/.tandem/state/stats.json" ]

  # CLAUDE.md created with tandem section
  [ -f "$HOME/.claude/CLAUDE.md" ]
  grep -q '<!-- tandem:start' "$HOME/.claude/CLAUDE.md"

  # Marker file written
  [ -f "$HOME/.tandem/.provisioned" ]

  # Output includes welcome message
  assert_output --partial "Welcome"
}

@test "first run: re-run is idempotent, nothing duplicated" {
  _clean_session_start

  # First run
  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"
  assert_success

  # Capture state after first run
  local rules_count_before
  rules_count_before=$(ls "$HOME/.claude/rules"/tandem-*.md 2>/dev/null | wc -l | tr -d ' ')
  local claude_md_before
  claude_md_before=$(cat "$HOME/.claude/CLAUDE.md")

  # Second run
  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"
  assert_success

  # Same number of rules files
  local rules_count_after
  rules_count_after=$(ls "$HOME/.claude/rules"/tandem-*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$rules_count_before" = "$rules_count_after" ]

  # CLAUDE.md not duplicated (only one tandem:start marker)
  local marker_count
  marker_count=$(grep -c '<!-- tandem:start' "$HOME/.claude/CLAUDE.md")
  [ "$marker_count" -eq 1 ]

  # CLAUDE.md content unchanged
  [ "$claude_md_before" = "$(cat "$HOME/.claude/CLAUDE.md")" ]

  # Second run should NOT show welcome (marker exists)
  refute_output --partial "Welcome"
}

@test "first run: version upgrade updates rules files" {
  _clean_session_start

  # First run to provision
  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"
  assert_success

  # Tamper with installed version in a rules file
  # The source files have "<!-- tandem v1.2.1 -->" on line 1
  # Change installed copy to a fake old version
  sed -i.bak 's/<!-- tandem v[^ ]* -->/<!-- tandem v0.0.1 -->/' "$HOME/.claude/rules/tandem-recall.md"
  rm -f "$HOME/.claude/rules/tandem-recall.md.bak"

  # Re-run
  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"
  assert_success

  # Installed version should now match source version again
  local installed_ver
  installed_ver=$(head -1 "$HOME/.claude/rules/tandem-recall.md" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
  local source_ver
  source_ver=$(head -1 "$PLUGIN_ROOT/rules/tandem-recall.md" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
  [ "$installed_ver" = "$source_ver" ]
}

@test "first run: CLAUDE.md created with correct tandem section content" {
  _clean_session_start

  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"
  assert_success

  # Has the start and end markers
  grep -q '<!-- tandem:start' "$HOME/.claude/CLAUDE.md"
  grep -q '<!-- tandem:end -->' "$HOME/.claude/CLAUDE.md"

  # Has the section heading
  grep -q '## Tandem' "$HOME/.claude/CLAUDE.md"

  # Has the progress.md instruction
  grep -q 'progress.md' "$HOME/.claude/CLAUDE.md"
}

@test "first run: stats.json initialised with correct structure" {
  _clean_session_start

  run_script_with_input "session-start.sh" "$(fixture_sessionstart)"
  assert_success

  # File is valid JSON
  jq empty "$HOME/.tandem/state/stats.json"

  # Has all expected keys
  local keys
  keys=$(jq -r 'keys[]' "$HOME/.tandem/state/stats.json" | sort | tr '\n' ',')
  [[ "$keys" == *"compactions"* ]]
  [[ "$keys" == *"first_session"* ]]
  [[ "$keys" == *"last_session"* ]]
  [[ "$keys" == *"milestones_hit"* ]]
  [[ "$keys" == *"total_sessions"* ]]

  # Values are correct types
  local total_sessions
  total_sessions=$(jq -r '.total_sessions' "$HOME/.tandem/state/stats.json")
  [ "$total_sessions" -eq 0 ]

  local milestones
  milestones=$(jq -r '.milestones_hit | length' "$HOME/.tandem/state/stats.json")
  [ "$milestones" -eq 0 ]
}
