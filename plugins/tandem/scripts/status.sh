#!/bin/bash
# Tandem status diagnostic. Read-only — no writes, no LLM calls.
# Outputs a formatted status block to stdout.

CWD="${1:-$(pwd)}"
MEMORY_DIR=$(tandem_memory_dir "$CWD")
PROGRESS_DIR=$(tandem_progress_dir "$CWD")
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
HOOKS_FILE="$PLUGIN_ROOT/hooks/hooks.json"
STATS_FILE="$HOME/.tandem/state/stats.json"

source "$PLUGIN_ROOT/lib/tandem.sh"

# --- Logo + Version ---

VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)

printf "\033[38;5;172m◎╵═╵◎\033[0m  \033[31mTandem v%s\033[0m\n" "$VERSION"
echo ""

# --- Pillar status ---

# Recall: check rules + hook
RECALL="not installed"
RECALL_RULES=0
RECALL_HOOK=0
[ -f "$HOME/.claude/rules/tandem-recall.md" ] && RECALL_RULES=1
if [ -f "$HOOKS_FILE" ] && grep -q 'session-end.sh' "$HOOKS_FILE" 2>/dev/null; then
  RECALL_HOOK=1
fi
if [ "$RECALL_RULES" -eq 1 ] && [ "$RECALL_HOOK" -eq 1 ]; then
  RECALL="installed"
elif [ "$RECALL_RULES" -eq 1 ] || [ "$RECALL_HOOK" -eq 1 ]; then
  RECALL="partially installed"
fi

printf "Recall ..... %s\n" "$RECALL"
echo ""

# --- Memory stats ---

if [ "$RECALL" != "not installed" ]; then
  if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
    MEM_LINES=$(wc -l < "$MEMORY_DIR/MEMORY.md" | tr -d ' ')
    MEM_EPOCH=$(tandem_file_mtime "$MEMORY_DIR/MEMORY.md")
    MEM_MTIME=$(date -r "$MEM_EPOCH" '+%b %d' 2>/dev/null || date -d "@$MEM_EPOCH" '+%b %d' 2>/dev/null)
    echo "Memory: MEMORY.md ${MEM_LINES} lines, last updated ${MEM_MTIME}"
  else
    echo "Memory: No MEMORY.md yet"
  fi

  # Progress
  if [ -f "$PROGRESS_DIR/progress.md" ]; then
    PROG_LINES=$(wc -l < "$PROGRESS_DIR/progress.md" | tr -d ' ')
    echo "Progress: ${PROG_LINES} lines (active)"
  fi

  # Global
  GLOBAL_FILE="$HOME/.tandem/memory/global.md"
  if [ -f "$GLOBAL_FILE" ]; then
    ENTRY_COUNT=$(grep -c '^## ' "$GLOBAL_FILE" 2>/dev/null)
    ENTRY_COUNT="${ENTRY_COUNT:-0}"
    GLOBAL_EPOCH=$(tandem_file_mtime "$GLOBAL_FILE")
    GLOBAL_MTIME=$(date -r "$GLOBAL_EPOCH" '+%b %d' 2>/dev/null || date -d "@$GLOBAL_EPOCH" '+%b %d' 2>/dev/null)
    echo "Global: ${ENTRY_COUNT} entries, last updated ${GLOBAL_MTIME}"
  else
    echo "Global: No cross-project activity logged yet"
  fi

  # Recurrence
  RECURRENCE_FILE="$HOME/.tandem/state/recurrence.json"
  if [ -f "$RECURRENCE_FILE" ]; then
    THEME_COUNT=$(jq '.themes | length' "$RECURRENCE_FILE" 2>/dev/null || echo 0)
    PROMO_COUNT=$(jq '[.themes | to_entries[] | select(.value.count >= 3)] | length' "$RECURRENCE_FILE" 2>/dev/null || echo 0)
    echo "Recurrence: ${THEME_COUNT} themes tracked, ${PROMO_COUNT} with count >= 3"
  fi

  echo ""
fi

# --- Stats ---

if [ -f "$STATS_FILE" ]; then
  TOTAL=$(jq -r '.total_sessions' "$STATS_FILE" 2>/dev/null)
  COMPACTIONS=$(jq -r '.compactions' "$STATS_FILE" 2>/dev/null)
  echo "Stats: ${TOTAL} sessions, ${COMPACTIONS} compactions"
fi

# --- Log info ---

TANDEM_LOG="$HOME/.tandem/logs/tandem.log"
echo ""
echo "Log: ${TANDEM_LOG}"
echo "  Level: ${TANDEM_LOG_LEVEL:-info} (set TANDEM_LOG_LEVEL to change)"
if [ -f "$TANDEM_LOG" ]; then
  LOG_LINES=$(wc -l < "$TANDEM_LOG" | tr -d ' ')
  YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '1 day ago' +%Y-%m-%d 2>/dev/null)
  ERROR_COUNT=0
  WARN_COUNT=0
  if [ -n "$YESTERDAY" ]; then
    ERROR_COUNT=$(awk -v cutoff="$YESTERDAY" '$1 >= cutoff && /\[ERROR\]/ { count++ } END { print count+0 }' "$TANDEM_LOG")
    WARN_COUNT=$(awk -v cutoff="$YESTERDAY" '$1 >= cutoff && /\[WARN \]/ { count++ } END { print count+0 }' "$TANDEM_LOG")
  fi
  echo "  Entries: ${LOG_LINES} total, ${ERROR_COUNT} errors / ${WARN_COUNT} warnings (24h)"
else
  echo "  No log file yet"
fi
