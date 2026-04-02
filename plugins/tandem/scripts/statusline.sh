#!/bin/bash
# Tandem status line for Claude Code.
# Replaces the default statusline with Tandem-aware indicators.
#
# Layout: ◎╵═╵◎  {branch}  ctx:{%}  {sessions}  prog: ✓ {age}  mem: ✓ {age}  {auto-commits}

input=$(cat)

# --- Colours ---
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
DIM="\033[2m"
RESET="\033[0m"

# --- Extract Claude Code data ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# --- Session directories ---
SESSIONS_DIR="$HOME/.tandem/sessions"

# --- Memory directory (same convention as Claude Code) ---
if [ -n "$cwd" ]; then
  sanitised=$(echo "$cwd" | sed 's|/|-|g')
  memory_dir="$HOME/.claude/projects/${sanitised}/memory"
else
  memory_dir=""
fi

# --- Progress directory (repo-scoped) ---
progress_dir=""
if [ -n "$cwd" ]; then
  git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_root" ]; then
    progress_dir="$git_root/.claude"
  else
    progress_dir="$HOME/.tandem/progress/$(echo "$cwd" | sed 's|/|-|g')"
  fi
fi

# --- Git branch ---
git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
fi

# --- Session heartbeat ---
if [ -n "$session_id" ] && [ -d "$SESSIONS_DIR/$session_id" ]; then
  state_file="$SESSIONS_DIR/$session_id/state.json"
  if [ -f "$state_file" ]; then
    # Extract task from progress.md for heartbeat
    hb_task=""
    if [ -n "$progress_dir" ] && [ -f "$progress_dir/progress.md" ]; then
      hb_task=$(sed -n 's/^\*\*Current task:\*\* *//p' "$progress_dir/progress.md" 2>/dev/null | head -1)
    fi

    now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    updates=".last_heartbeat = \"$now_utc\""
    [ -n "$hb_task" ] && updates="$updates | .current_task = $(echo "$hb_task" | jq -R .)"
    [ -n "$git_branch" ] && updates="$updates | .branch = \"$git_branch\""

    updated=$(jq "$updates" "$state_file" 2>/dev/null)
    [ -n "$updated" ] && echo "$updated" > "$state_file"
  fi
fi

# --- Orphan cleanup (every 10th render, tracked by counter file) ---
RENDER_COUNTER="$HOME/.tandem/state/.statusline-renders"
render_count=0
if [ -f "$RENDER_COUNTER" ]; then
  render_count=$(cat "$RENDER_COUNTER" 2>/dev/null)
  render_count=$((render_count + 1))
else
  mkdir -p "$(dirname "$RENDER_COUNTER")"
  render_count=1
fi
echo "$render_count" > "$RENDER_COUNTER"

if [ $((render_count % 10)) -eq 0 ] && [ -d "$SESSIONS_DIR" ]; then
  for orphan_dir in "$SESSIONS_DIR"/*/; do
    [ ! -d "$orphan_dir" ] && continue
    orphan_state="$orphan_dir/state.json"
    [ ! -f "$orphan_state" ] && continue
    orphan_pid=$(jq -r '.pid // empty' "$orphan_state" 2>/dev/null)
    [ -z "$orphan_pid" ] && { rm -rf "$orphan_dir"; continue; }
    if ! kill -0 "$orphan_pid" 2>/dev/null; then
      rm -rf "$orphan_dir"
    fi
  done
fi

# --- Count sibling sessions (same project, excluding self) ---
sibling_count=0
if [ -n "$cwd" ] && [ -d "$SESSIONS_DIR" ]; then
  for sib_dir in "$SESSIONS_DIR"/*/; do
    [ ! -d "$sib_dir" ] && continue
    sib_state="$sib_dir/state.json"
    [ ! -f "$sib_state" ] && continue
    sib_id=$(basename "$sib_dir")
    [ "$sib_id" = "$session_id" ] && continue
    sib_project=$(jq -r '.project // empty' "$sib_state" 2>/dev/null)
    [ "$sib_project" != "$cwd" ] && continue
    sib_pid=$(jq -r '.pid // empty' "$sib_state" 2>/dev/null)
    [ -z "$sib_pid" ] && continue
    kill -0 "$sib_pid" 2>/dev/null || continue
    sibling_count=$((sibling_count + 1))
  done
fi

# --- Relative age helper ---
_relative_age() {
  local mtime="$1"
  [ -z "$mtime" ] && return
  local now age
  now=$(date +%s)
  age=$((now - mtime))
  if [ "$age" -lt 60 ]; then printf "<1m"
  elif [ "$age" -lt 3600 ]; then printf "%dm" "$((age / 60))"
  elif [ "$age" -lt 86400 ]; then printf "%dh" "$((age / 3600))"
  elif [ "$age" -lt 2592000 ]; then printf "%dd" "$((age / 86400))"
  else printf ">30d"
  fi
}

# --- Build output ---
out="◎╵═╵◎"

# Branch
if [ -n "$git_branch" ]; then
  out="${out}   ${git_branch}"
fi

# Context remaining %
if [ -n "$remaining" ]; then
  remaining_int=$(printf "%.0f" "$remaining")
  if [ "$remaining_int" -lt 20 ]; then
    colour="$RED"
  elif [ "$remaining_int" -lt 50 ]; then
    colour="$YELLOW"
  else
    colour="$GREEN"
  fi
  out="${out}  ${colour}ctx:${remaining_int}%${RESET}"
fi

# Session count (only shown when siblings exist)
if [ "$sibling_count" -gt 0 ]; then
  total=$((sibling_count + 1))
  out="${out}  ${YELLOW}${total} sessions${RESET}"
fi

# Progress health
if [ -n "$progress_dir" ] && [ -f "$progress_dir/progress.md" ] && grep -q '<!-- working-state:start -->' "$progress_dir/progress.md" 2>/dev/null; then
  prog_mtime=$(stat -f '%m' "$progress_dir/progress.md" 2>/dev/null || stat -c '%Y' "$progress_dir/progress.md" 2>/dev/null)
  prog_age=$(_relative_age "$prog_mtime")
  # Count session log entries (lines starting with - after working-state block)
  prog_logs=$(sed -n '/<!-- working-state:end -->/,$ { /^- /p; }' "$progress_dir/progress.md" 2>/dev/null | wc -l | tr -d ' ')
  out="${out}  prog: ${GREEN}✓ ${prog_age} ${prog_logs}log${RESET}"
else
  out="${out}  prog: ${RED}✗${RESET}"
fi

# Memory health
if [ -n "$memory_dir" ] && [ -f "$memory_dir/MEMORY.md" ]; then
  mem_lines=$(wc -l < "$memory_dir/MEMORY.md" | tr -d ' ')
  refusal=$(head -1 "$memory_dir/MEMORY.md" | grep -qiE "^(I cannot|I'm sorry|I am sorry|As an AI|I understand|I'm unable)" && echo 1 || echo 0)
  mem_mtime=$(stat -f '%m' "$memory_dir/MEMORY.md" 2>/dev/null || stat -c '%Y' "$memory_dir/MEMORY.md" 2>/dev/null)
  mem_age=$(_relative_age "$mem_mtime")
  # Count sections and priority markers
  mem_sections=$(grep -c '^## ' "$memory_dir/MEMORY.md" 2>/dev/null); mem_sections=${mem_sections:-0}
  mem_p1=$(grep -c '\[P1\]' "$memory_dir/MEMORY.md" 2>/dev/null); mem_p1=${mem_p1:-0}
  mem_p2=$(grep -c '\[P2\]' "$memory_dir/MEMORY.md" 2>/dev/null); mem_p2=${mem_p2:-0}
  mem_detail="${mem_age} ${mem_lines}L ${mem_sections}§"
  # Show priority breakdown only if priorities are in use
  if [ "$mem_p1" -gt 0 ] || [ "$mem_p2" -gt 0 ]; then
    mem_detail="${mem_detail} ${mem_p1}P1 ${mem_p2}P2"
  fi
  if [ "$mem_lines" -gt 5 ] && [ "$refusal" -eq 0 ]; then
    out="${out}  mem: ${GREEN}✓ ${mem_detail}${RESET}"
  else
    out="${out}  mem: ${RED}✗ ${mem_detail}${RESET}"
  fi
else
  out="${out}  mem: ${RED}✗${RESET}"
fi

# Auto-commits
if [ -n "$cwd" ] && [ -n "$git_branch" ]; then
  ac_count=0
  while true; do
    ac_subj=$(git -C "$cwd" --no-optional-locks log -1 --format="%s" "HEAD~${ac_count}" 2>/dev/null) || break
    case "$ac_subj" in
      claude\(checkpoint\):*|"chore(tandem): session checkpoint"|"chore(tandem): session context")
        ac_count=$((ac_count + 1))
        ;;
      *)
        # Check for Tandem-Auto-Commit trailer
        if git -C "$cwd" --no-optional-locks log -1 --format='%B' "HEAD~${ac_count}" 2>/dev/null | grep -q 'Tandem-Auto-Commit: true'; then
          ac_count=$((ac_count + 1))
        else
          break
        fi
        ;;
    esac
    # Safety cap
    [ "$ac_count" -ge 50 ] && break
  done

  if [ "$ac_count" -gt 0 ]; then
    latest_msg=$(git -C "$cwd" --no-optional-locks log -1 --format="%s" 2>/dev/null)
    # Truncate long messages
    if [ ${#latest_msg} -gt 50 ]; then
      latest_msg="${latest_msg:0:47}..."
    fi
    out="${out}  ${DIM}${latest_msg}"
    extra=$((ac_count - 1))
    if [ "$extra" -gt 0 ]; then
      out="${out} + ${extra} more"
    fi
    out="${out}${RESET}"
  fi
fi

printf "%b" "$out"
