#!/usr/bin/env bash
# Stop hook (Claude Code and Codex): when the session log has gone stale,
# send the agent back once to add an entry. Quiet unless all of these hold:
#   - this stop is not already a continuation from a Stop hook;
#   - 20 minutes have passed since the session's first reply (the first
#     stop only starts the clock);
#   - the log has not changed in 20 minutes;
#   - this hook has not asked in the last 20 minutes.

WINDOW=1200

input=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null)" = "true" ] && exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
log="$root/.agents/progress.md"

session=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
[ -n "$session" ] || exit 0
mark="${TMPDIR:-/tmp}/tandem-log-check-$session"

# Seconds since a file last changed (GNU stat first, then BSD stat).
age() { echo $(( $(date +%s) - $(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1") )); }

if [ ! -e "$mark" ]; then
  touch "$mark"
  exit 0
fi
[ "$(age "$mark")" -lt "$WINDOW" ] && exit 0
[ -f "$log" ] && [ "$(age "$log")" -lt "$WINDOW" ] && exit 0

touch "$mark"
jq -n --arg log "$log" '{
  decision: "block",
  reason: ("Session log check: add a short entry to " + $log + " covering what you decided, changed or learned since the last entry, and why. If nothing is worth keeping, say so in one line and stop.")
}'
exit 0
