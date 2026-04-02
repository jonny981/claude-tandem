#!/bin/bash
# Shared test helpers: HOME isolation, mock setup, convenience functions.
# Source at top of every .bats file:
#   load '../helpers/test_helper'

# ─── Bats libraries ────────────────────────────────────────────────────────

BATS_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
load "${BATS_TEST_DIR}/lib/bats-support/load"
load "${BATS_TEST_DIR}/lib/bats-assert/load"

# ─── Project paths ─────────────────────────────────────────────────────────

export PLUGIN_ROOT="$(cd "${BATS_TEST_DIR}/../plugins/tandem" && pwd)"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# ─── HOME isolation ────────────────────────────────────────────────────────

setup() {
  export ORIGINAL_HOME="$HOME"
  export ORIGINAL_PATH="$PATH"
  export TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR/home"

  # Standard dirs
  mkdir -p "$HOME/.tandem/logs"
  mkdir -p "$HOME/.tandem/state"
  mkdir -p "$HOME/.claude/rules"

  # Fake project CWD
  export TEST_CWD="$TEST_TEMP_DIR/project"
  mkdir -p "$TEST_CWD"

  # Compute memory dir (same convention as scripts)
  local sanitised
  sanitised=$(echo "$TEST_CWD" | sed 's|/|-|g')
  export TEST_MEMORY_DIR="$HOME/.claude/projects/${sanitised}/memory"
  mkdir -p "$TEST_MEMORY_DIR"

  # Progress dir: non-git fallback (matches tandem_progress_dir for non-git CWD)
  local progress_slug
  progress_slug=$(echo "$TEST_CWD" | sed 's|/|-|g')
  export TEST_PROGRESS_DIR="$HOME/.tandem/progress/${progress_slug}"
  mkdir -p "$TEST_PROGRESS_DIR"

  # Install no-op mock claude on PATH
  _install_mock_claude "mock response"

  # Clean environment
  unset TANDEM_WORKER
  unset TANDEM_LLM_BACKEND
  unset TANDEM_LLM_MODEL
  unset TANDEM_LLM_API_KEY
  unset TANDEM_LOG_LEVEL
}

teardown() {
  export HOME="$ORIGINAL_HOME"
  export PATH="$ORIGINAL_PATH"
  rm -rf "$TEST_TEMP_DIR"
}

# ─── Convenience helpers ───────────────────────────────────────────────────

# Run a hook script with JSON on stdin
run_script_with_input() {
  local script="$1"
  local json="$2"
  run bash -c "echo '$json' | '$PLUGIN_ROOT/scripts/$script'"
}

# Create progress.md with optional age (seconds in the past)
create_progress() {
  local content="$1"
  local age_seconds="${2:-0}"

  echo "$content" > "$TEST_PROGRESS_DIR/progress.md"

  if [ "$age_seconds" -gt 0 ]; then
    local past_time
    past_time=$(($(date +%s) - age_seconds))
    touch -t "$(date -r "$past_time" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$past_time" '+%Y%m%d%H%M.%S' 2>/dev/null)" "$TEST_PROGRESS_DIR/progress.md" 2>/dev/null || true
  fi
}

# Create MEMORY.md
create_memory() {
  local content="$1"
  echo "$content" > "$TEST_MEMORY_DIR/MEMORY.md"
}

# Create stats.json
create_stats() {
  local sessions="${1:-0}"
  local compactions="${2:-0}"
  cat > "$HOME/.tandem/state/stats.json" <<STATS_EOF
{
  "total_sessions": $sessions,
  "first_session": "2025-01-01",
  "last_session": "2025-01-01",
  "compactions": $compactions,
  "milestones_hit": []
}
STATS_EOF
}

# Initialise a git repo in TEST_CWD with an initial commit
init_test_git_repo() {
  git -C "$TEST_CWD" init -q -b main
  git -C "$TEST_CWD" config user.email "test@test.com"
  git -C "$TEST_CWD" config user.name "Test"
  echo "init" > "$TEST_CWD/README.md"
  git -C "$TEST_CWD" add README.md
  git -C "$TEST_CWD" commit -q -m "$(printf 'chore: initial commit\n\nBootstrap test repo.')"
  # Update progress dir to git-root location (matches tandem_progress_dir for git repos)
  export TEST_PROGRESS_DIR="$TEST_CWD/.claude"
  mkdir -p "$TEST_PROGRESS_DIR"
}

# Create a git commit in TEST_CWD with given subject and optional body
make_commit() {
  local subject="$1"
  local body="${2:-}"
  local trailer="${3:-}"

  echo "$(date +%s%N)" >> "$TEST_CWD/README.md"
  git -C "$TEST_CWD" add README.md

  local msg="$subject"
  if [ -n "$body" ]; then
    msg="$(printf '%s\n\n%s' "$subject" "$body")"
  fi
  if [ -n "$trailer" ]; then
    msg="$(printf '%s\n\n%s' "$msg" "$trailer")"
  fi

  git -C "$TEST_CWD" commit -q -m "$msg"
}

# Create an auto-commit (Tandem checkpoint style)
make_auto_commit() {
  make_commit "chore(tandem): session checkpoint" "Session progress notes here." "Tandem-Auto-Commit: true"
}

# Get the path to a fixture file
fixture_path() {
  echo "${BATS_TEST_DIR}/fixtures/$1"
}
