#!/usr/bin/env bash
# PreCompact hook (Claude Code and Codex): if the agent has not written the
# session log in the last 2 minutes, ask Claude Haiku to summarise the end of
# the conversation and append it, so compaction cannot lose the thread.
# Writes nothing if Haiku answers SKIP or the call fails.

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$transcript" ] || exit 0
command -v claude >/dev/null 2>&1 || exit 0
log="$root/.agents/progress.md"

if [ -f "$log" ]; then
  modified=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log")
  [ $(( $(date +%s) - modified )) -lt 120 ] && exit 0
fi

prompt="You write entries for a coding session's append-only log. Below is the end of the session transcript (JSONL). If nothing substantive happened, reply with exactly SKIP. Otherwise reply with 3 to 8 short bullet points: what is being worked on, decisions made and why, anything tried and dropped, and the next step. Be specific: names, file paths, numbers. No preamble.

<transcript>
$(tail -c 20000 "$transcript")
</transcript>"

# Settings, hooks and tools are off, so this call cannot re-enter Tandem.
summary=$(printf '%s' "$prompt" | claude -p --model haiku --max-budget-usd 0.15 \
  --system-prompt "" --tools "" --setting-sources "" --disable-slash-commands \
  --no-chrome --no-session-persistence 2>/dev/null) || exit 0
case "$summary" in "" | SKIP | Error:*) exit 0 ;; esac

mkdir -p "$root/.agents"
printf '\n## %s: captured before compaction\n\n%s\n' "$(date '+%Y-%m-%d %H:%M')" "$summary" >> "$log"
exit 0
