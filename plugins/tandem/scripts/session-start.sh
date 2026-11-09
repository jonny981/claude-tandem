#!/usr/bin/env bash
# SessionStart hook (Claude Code and Codex): point the agent at the repo's
# append-only session log and replay its latest entries. Runs on startup,
# resume, /clear and after compaction. Both tools add plain stdout to the
# model's context. Outside a git repo it does nothing.

cwd=$(jq -r '.cwd // empty' 2>/dev/null)
root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
log="$root/.agents/progress.md"

echo "Session log: $log (append-only). Add an entry when you make a decision, change approach, hit a constraint, get corrected, or finish a piece of work."
if [ -s "$log" ]; then
  echo "Latest entries:"
  tail -n 150 "$log"
fi
exit 0
