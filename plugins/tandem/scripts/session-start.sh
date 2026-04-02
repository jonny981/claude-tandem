#!/bin/bash
# SessionStart hook: first-run provisioning + stale progress detection + status indicators.
# Outputs to stdout are injected into Claude's context.
#
# Output format: single ◎╵═╵◎ header line, then plain detail lines underneath.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && exit 0

# Compute memory and progress directories
MEMORY_DIR=$(tandem_memory_dir "$CWD")
PROGRESS_DIR=$(tandem_progress_dir "$CWD")

RULES_DIR="$HOME/.claude/rules"
MARKER_FILE="$HOME/.tandem/.provisioned"

# ==========================================================================
# Phase 1: Silent work (no output)
# ==========================================================================

# --- First-run provisioning ---

FIRST_RUN=0
if [ ! -f "$MARKER_FILE" ]; then
  PROVISIONED=0

  if [ -f "$PLUGIN_ROOT/rules/tandem-recall.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-recall.md" "$RULES_DIR/tandem-recall.md"
    PROVISIONED=1
  fi

  if [ -f "$PLUGIN_ROOT/rules/tandem-display.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-display.md" "$RULES_DIR/tandem-display.md"
    PROVISIONED=1
  fi

  if [ -f "$PLUGIN_ROOT/rules/tandem-commits.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-commits.md" "$RULES_DIR/tandem-commits.md"
    PROVISIONED=1
  fi

  if [ -f "$PLUGIN_ROOT/rules/tandem-debugging.md" ]; then
    mkdir -p "$RULES_DIR"
    cp "$PLUGIN_ROOT/rules/tandem-debugging.md" "$RULES_DIR/tandem-debugging.md"
    PROVISIONED=1
  fi

  # Statusline script
  if [ -f "$PLUGIN_ROOT/scripts/statusline.sh" ]; then
    mkdir -p "$HOME/.tandem/bin"
    cp "$PLUGIN_ROOT/scripts/statusline.sh" "$HOME/.tandem/bin/statusline.sh"
    chmod +x "$HOME/.tandem/bin/statusline.sh"
    PROVISIONED=1
  fi

  if [ "$PROVISIONED" -eq 1 ]; then
    mkdir -p "$(dirname "$MARKER_FILE")"
    date +%s > "$MARKER_FILE"
    tandem_log info "provisioned rules"
    FIRST_RUN=1
  fi
fi

# --- Session registration ---

# Clean up orphaned sessions before registering
tandem_cleanup_orphans

# Derive session_id from Claude Code's session_id (in stdin JSON) or fallback
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && SESSION_ID="${PPID}-$(date +%s)"
tandem_session_register "$CWD" "$SESSION_ID"

# --- Initialize stats ---

if [ ! -f "$HOME/.tandem/state/stats.json" ]; then
  mkdir -p "$HOME/.tandem/state"
  jq -n '{
    total_sessions: 0,
    first_session: (now | strftime("%Y-%m-%d")),
    last_session: (now | strftime("%Y-%m-%d")),
    compactions: 0,
    milestones_hit: []
  }' > "$HOME/.tandem/state/stats.json"
fi

# --- Statusline setting (idempotent) ---

STATUSLINE_SCRIPT="$HOME/.tandem/bin/statusline.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$STATUSLINE_SCRIPT" ] && [ -f "$SETTINGS_FILE" ]; then
  CURRENT_SL=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
  if [ "$CURRENT_SL" != "$STATUSLINE_SCRIPT" ]; then
    TMPFILE=$(mktemp)
    if jq --arg cmd "$STATUSLINE_SCRIPT" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS_FILE" > "$TMPFILE" 2>/dev/null && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$SETTINGS_FILE"
      tandem_log info "configured statusLine in settings.json"
    else
      rm -f "$TMPFILE"
    fi
  fi
fi

# --- Statusline script upgrade (keep in sync with plugin source) ---

if [ -f "$PLUGIN_ROOT/scripts/statusline.sh" ] && [ -f "$STATUSLINE_SCRIPT" ]; then
  if ! cmp -s "$PLUGIN_ROOT/scripts/statusline.sh" "$STATUSLINE_SCRIPT"; then
    cp "$PLUGIN_ROOT/scripts/statusline.sh" "$STATUSLINE_SCRIPT"
    chmod +x "$STATUSLINE_SCRIPT"
    tandem_log info "upgraded statusline script"
  fi
fi

# --- Version-based rules upgrade ---

PLUGIN_VERSION=$(jq -r '.version // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
if [ -n "$PLUGIN_VERSION" ]; then
  for RULES_FILE in "$RULES_DIR"/tandem-*.md; do
    [ -f "$RULES_FILE" ] || continue
    BASENAME=$(basename "$RULES_FILE")
    SOURCE="$PLUGIN_ROOT/rules/$BASENAME"
    [ -f "$SOURCE" ] || continue

    INSTALLED_VER=$(head -1 "$RULES_FILE" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')
    SOURCE_VER=$(head -1 "$SOURCE" | sed -n 's/.*<!-- tandem v\([^ ]*\) -->.*/\1/p')

    if [ -n "$SOURCE_VER" ] && [ "$INSTALLED_VER" != "$SOURCE_VER" ]; then
      cp "$SOURCE" "$RULES_FILE"
      tandem_log info "upgraded rules file: $BASENAME ($INSTALLED_VER -> $SOURCE_VER)"
    fi
  done
fi

# --- Clean up legacy files from previous Tandem versions ---
rm -f "$HOME/.tandem/bin/detect-raw-input.sh" 2>/dev/null
rm -f "$RULES_DIR/tandem-clarify.md" 2>/dev/null
rm -f "$RULES_DIR/tandem-grow.md" 2>/dev/null

# --- Migrate progress.md from auto-memory to repo-scoped location ---
OLD_PROGRESS="$MEMORY_DIR/progress.md"
NEW_PROGRESS="$PROGRESS_DIR/progress.md"

if [ -f "$OLD_PROGRESS" ] && [ ! -f "$NEW_PROGRESS" ]; then
  mkdir -p "$PROGRESS_DIR"
  cp "$OLD_PROGRESS" "$NEW_PROGRESS"
  rm -f "$OLD_PROGRESS"
  tandem_log info "migrated progress.md to $PROGRESS_DIR"
elif [ -f "$OLD_PROGRESS" ] && [ -f "$NEW_PROGRESS" ]; then
  rm -f "$OLD_PROGRESS"
  tandem_log info "removed stale progress.md from auto-memory"
fi

# --- Ensure .claude/progress.md is gitignored ---
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$GIT_ROOT" ]; then
  CLAUDE_GITIGNORE="$GIT_ROOT/.claude/.gitignore"
  if [ ! -f "$CLAUDE_GITIGNORE" ] || ! grep -q '^progress\.md$' "$CLAUDE_GITIGNORE" 2>/dev/null; then
    mkdir -p "$GIT_ROOT/.claude"
    echo "progress.md" >> "$CLAUDE_GITIGNORE"
    tandem_log info "added progress.md to .claude/.gitignore"
  fi
fi

# --- CLAUDE.md section injection ---

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TANDEM_VERSION="v${PLUGIN_VERSION:-1.2.0}"
TANDEM_SECTION="<!-- tandem:start ${TANDEM_VERSION} -->
## Tandem — Session Progress
Read .claude/progress.md (at the repo root) for current session state. Maintain it with two parts: a rewritable Working State section (between \`<!-- working-state:start/end -->\` markers) capturing current task, approach, blockers, and key files, plus an append-only Session Log below. Create it on your first significant action if it doesn't exist. Update Working State on plan mode transitions, not just code changes. Planning and decision-making are progress. This enables memory continuity between sessions.
<!-- tandem:end -->"

if [ ! -f "$CLAUDE_MD" ]; then
  mkdir -p "$(dirname "$CLAUDE_MD")"
  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    printf '%s\n' "$TANDEM_SECTION" > "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$CLAUDE_MD"
    else
      tandem_log warn "failed to write CLAUDE.md temp file"
      rm -f "$TMPFILE"
    fi
  else
    tandem_log warn "failed to create temp file for CLAUDE.md"
  fi
elif ! grep -q '<!-- tandem:start' "$CLAUDE_MD"; then
  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    cp "$CLAUDE_MD" "$TMPFILE"
    printf '\n%s\n' "$TANDEM_SECTION" >> "$TMPFILE"
    if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
      mv "$TMPFILE" "$CLAUDE_MD"
    else
      tandem_log warn "failed to write CLAUDE.md temp file"
      rm -f "$TMPFILE"
    fi
  else
    tandem_log warn "failed to create temp file for CLAUDE.md"
  fi
else
  INSTALLED_TANDEM_VER=$(sed -n 's/.*<!-- tandem:start \(v[^ ]*\) -->.*/\1/p' "$CLAUDE_MD")
  if [ "$INSTALLED_TANDEM_VER" != "$TANDEM_VERSION" ]; then
    TMPFILE=$(mktemp)
    if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
      TANDEM_SECTION="$TANDEM_SECTION" awk '
        /<!-- tandem:start/ { skip=1; printed=0; next }
        /<!-- tandem:end -->/ { if (!printed) { print ENVIRON["TANDEM_SECTION"]; printed=1 }; skip=0; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$TMPFILE"
      if [ $? -eq 0 ] && [ -s "$TMPFILE" ]; then
        mv "$TMPFILE" "$CLAUDE_MD"
      else
        tandem_log warn "failed to write CLAUDE.md version update"
        rm -f "$TMPFILE"
      fi
    else
      tandem_log warn "failed to create temp file for CLAUDE.md version update"
    fi
  fi
fi

# --- Post-compaction state recovery (outputs directly, before Tandem block) ---

if [ -f "$PROGRESS_DIR/progress.md" ] && grep -q '## Pre-compaction State' "$PROGRESS_DIR/progress.md"; then
  # Prefer structured Working State over free-form Pre-compaction State
  STATE_CONTENT=""
  if grep -q '<!-- working-state:start -->' "$PROGRESS_DIR/progress.md" 2>/dev/null; then
    STATE_CONTENT=$(sed -n '/<!-- working-state:start -->/,/<!-- working-state:end -->/p' \
      "$PROGRESS_DIR/progress.md" | grep -v '<!-- working-state')
  fi

  # Fall back to Pre-compaction State if no structured state
  if [ -z "$STATE_CONTENT" ]; then
    STATE_CONTENT=$(sed -n '/^## Pre-compaction State$/,/^## /{ /^## Pre-compaction State$/d; /^## /d; p; }' "$PROGRESS_DIR/progress.md")
    if [ -z "$STATE_CONTENT" ]; then
      STATE_CONTENT=$(sed -n '/^## Pre-compaction State$/,$p' "$PROGRESS_DIR/progress.md" | tail -n +2)
    fi
  fi

  if [ -n "$STATE_CONTENT" ]; then
    echo "Resuming. Before compaction you were:"
    echo "$STATE_CONTENT"
  fi

  TMPFILE=$(mktemp)
  if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
    sed '/^## Auto-captured (pre-compaction)$/,$d; /^## Pre-compaction State$/,$d' "$PROGRESS_DIR/progress.md" > "$TMPFILE"
    if [ $? -eq 0 ]; then
      sed -i.bak -e :a -e '/^\n*$/{$d;N;ba;}' "$TMPFILE" 2>/dev/null || sed -e :a -e '/^\n*$/{$d;N;ba;}' "$TMPFILE" > "${TMPFILE}.clean" && mv "${TMPFILE}.clean" "$TMPFILE"
      rm -f "${TMPFILE}.bak"
      mv "$TMPFILE" "$PROGRESS_DIR/progress.md"
    else
      tandem_log warn "failed to strip state section from progress.md"
      rm -f "$TMPFILE"
    fi
  else
    tandem_log warn "failed to create temp file for progress.md state cleanup"
  fi
elif [ -f "$PROGRESS_DIR/progress.md" ] && grep -q '<!-- working-state:start -->' "$PROGRESS_DIR/progress.md" 2>/dev/null; then
  # Previous session ended without compaction — Working State markers still present
  STATE_CONTENT=$(sed -n '/<!-- working-state:start -->/,/<!-- working-state:end -->/p' \
    "$PROGRESS_DIR/progress.md" | grep -v '<!-- working-state')
  if [ -n "$STATE_CONTENT" ]; then
    echo "Continuing from previous session:"
    echo "$STATE_CONTENT"
  fi
fi

# --- Increment session stats (only on startup, not resume/compact/clear) ---

SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
STATS_FILE="$HOME/.tandem/state/stats.json"
if [ -f "$STATS_FILE" ]; then
  if [ "$SOURCE" = "startup" ]; then
    NEW_STATS=$(jq --arg today "$(date +%Y-%m-%d)" '
      .total_sessions += 1 |
      .last_session = $today
    ' "$STATS_FILE")
    tandem_log debug "Session count incremented (source=$SOURCE, new_total=$(echo "$NEW_STATS" | jq -r '.total_sessions'))"

    TMPFILE=$(mktemp "$STATS_FILE.XXXXXX")
    if [ -n "$TMPFILE" ] && [ -f "$TMPFILE" ]; then
      if echo "$NEW_STATS" > "$TMPFILE" && [ -s "$TMPFILE" ]; then
        mv "$TMPFILE" "$STATS_FILE"
      else
        rm -f "$TMPFILE"
      fi
    fi
  else
    NEW_STATS=$(cat "$STATS_FILE")
  fi
fi

# --- MEMORY.md corruption detection and rollback ---

if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  LINE_COUNT=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
  REFUSAL_PATTERN=$(head -1 "$MEMORY_DIR/MEMORY.md" | grep -qiE '^(I cannot|I'"'"'m sorry|I am sorry|As an AI)' && echo 1 || echo 0)

  if [ "$LINE_COUNT" -lt 5 ] || [ "$REFUSAL_PATTERN" -eq 1 ]; then
    LATEST_BACKUP=$(ls -t "$MEMORY_DIR"/.MEMORY.md.backup-* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
      tandem_log warn "corrupted MEMORY.md detected (${LINE_COUNT} lines). Rolling back to backup."
      mv "$LATEST_BACKUP" "$MEMORY_DIR/MEMORY.md"
      MEMORY_ROLLED_BACK=1
    else
      tandem_log warn "corrupted MEMORY.md detected but no backup available"
    fi
  fi
fi

# ==========================================================================
# Phase 2: Output (header line first, then plain detail lines)
# ==========================================================================

# --- Header (always first, always output) ---

tandem_header "$MEMORY_DIR" "$PROGRESS_DIR"

# --- Detail lines (plain, no logo) ---

# CWD is not a git root — memory may land in the wrong project
if ! git -C "$CWD" rev-parse --show-toplevel &>/dev/null || \
   [ "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" != "$CWD" ]; then
  echo "Note: CWD is not a git root. Memory is scoped to $(basename "$CWD")/. Start Claude Code from your project root for accurate memory scoping."
fi

# First run welcome
if [ "$FIRST_RUN" -eq 1 ]; then
  echo "Welcome! Run /tandem:status to get started."
fi

# Sibling sessions
SIBLINGS=$(tandem_sibling_sessions "$CWD" "$SESSION_ID")
if [ -n "$SIBLINGS" ]; then
  SIBLING_COUNT=$(echo "$SIBLINGS" | wc -l | tr -d ' ')
  echo "Active sessions on this project: $SIBLING_COUNT sibling(s)"
  for sid in $SIBLINGS; do
    local_state="$TANDEM_SESSIONS_DIR/$sid/state.json"
    if [ -f "$local_state" ]; then
      s_branch=$(jq -r '.branch // "?"' "$local_state" 2>/dev/null)
      s_task=$(jq -r '.current_task // ""' "$local_state" 2>/dev/null)
      s_info="  - $sid: $s_branch"
      [ -n "$s_task" ] && s_info="$s_info, $s_task"
      echo "$s_info"
    fi
  done
fi

# Corruption rollback notice
if [ "${MEMORY_ROLLED_BACK:-0}" -eq 1 ]; then
  echo "Corrupted MEMORY.md detected. Rolled back to backup."
fi

# Milestones
if [ -n "${NEW_STATS:-}" ]; then
  TOTAL=$(echo "$NEW_STATS" | jq -r '.total_sessions')
  MILESTONES_HIT=$(echo "$NEW_STATS" | jq -r '.milestones_hit | join(",")')

  for MILESTONE in 10 50 100 500 1000; do
    if [ "$TOTAL" -eq "$MILESTONE" ] && ! echo "$MILESTONES_HIT" | grep -q "$MILESTONE"; then
      COMPACTIONS=$(echo "$NEW_STATS" | jq -r '.compactions')
      echo "Milestone: ${MILESTONE} sessions! ${COMPACTIONS} compactions."
      jq ".milestones_hit += [\"$MILESTONE\"]" "$STATS_FILE" > "$STATS_FILE.tmp"
      mv "$STATS_FILE.tmp" "$STATS_FILE"
    fi
  done

fi

# Last session recap
RECAP_FILE="$HOME/.tandem/.last-session-recap"
if [ -f "$RECAP_FILE" ]; then
  LINES=$(grep '^memory_lines:' "$RECAP_FILE" 2>/dev/null | cut -d' ' -f2)
  if [ -n "$LINES" ]; then
    echo "Last session: memory at ${LINES} lines."
  fi
  rm -f "$RECAP_FILE"
fi

# Health check (only errors from current version)
TANDEM_LOG="$HOME/.tandem/logs/tandem.log"
if [ -f "$TANDEM_LOG" ] && [ -n "$PLUGIN_VERSION" ]; then
  ISSUE_COUNT=$(grep -c "\[$PLUGIN_VERSION\].*\(\[ERROR\]\|\[WARN \]\)" "$TANDEM_LOG" 2>/dev/null)
  ISSUE_COUNT="${ISSUE_COUNT:-0}"
  if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo "${ISSUE_COUNT} issue(s) logged. Run /tandem:logs errors to review."
  fi
fi

# Recalled indicator
if [ -f "$MEMORY_DIR/.tandem-last-compaction" ]; then
  if [ -f "$HOME/.tandem/state/stats.json" ]; then
    TOTAL_COMPACTIONS=$(jq -r '.compactions' "$HOME/.tandem/state/stats.json")
    echo "Recalled. (${TOTAL_COMPACTIONS} compactions total)"
  else
    echo "Recalled."
  fi
  rm -f "$MEMORY_DIR/.tandem-last-compaction"
fi

# Recurrence alerts
RECURRENCE_FILE="$HOME/.tandem/state/recurrence.json"
if [ -f "$RECURRENCE_FILE" ]; then
  PROMOTIONS=$(jq -r '
    [.themes | to_entries[] | select(.value.count >= 3) | "\(.key) (\(.value.count) sessions)"]
    | join(", ")
  ' "$RECURRENCE_FILE" 2>/dev/null)
  if [ -n "$PROMOTIONS" ]; then
    echo "Recurring: ${PROMOTIONS}. Run /tandem:recall promote to make permanent."
  fi
fi

# Cross-project context
GLOBAL_FILE="$HOME/.tandem/memory/global.md"
if [ -f "$GLOBAL_FILE" ]; then
  PROJECT_NAME=$(basename "$CWD")
  OTHER_ENTRIES=$(sed 's/ [–—] / -- /g' "$GLOBAL_FILE" | awk -v proj="$PROJECT_NAME" '
    /^## / {
      sub(/^## /, "")
      idx = index($0, " -- ")
      if (idx > 0) {
        date = substr($0, 1, idx - 1)
        name = substr($0, idx + 4)
        getline summary
        if (name != proj && count < 5) {
          split(date, d, "-")
          months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"
          split(months, mnames, " ")
          mon = mnames[int(d[2])]
          printf "- %s (%s %s): %s\n", name, mon, int(d[3]), summary
          count++
        }
      }
    }
  ')

  if [ -n "$OTHER_ENTRIES" ]; then
    echo ""
    echo "Context from other projects:"
    echo "$OTHER_ENTRIES"
  fi
fi

# Stale progress detection
if [ -f "$PROGRESS_DIR/progress.md" ]; then
  PROGRESS_MTIME=$(tandem_file_mtime "$PROGRESS_DIR/progress.md")
  SESSION_START=$(date +%s)

  if [ -n "$PROGRESS_MTIME" ]; then
    AGE=$((SESSION_START - PROGRESS_MTIME))
    if [ "$AGE" -gt 300 ]; then
      echo "Previous session notes found. Context carried forward."
    fi
  fi
fi

exit 0
