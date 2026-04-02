#!/bin/bash
# PostToolUse hook: detects git push and gh pr create, prompts PR summary updates.
# Claude condenses commit bodies into a scannable PR description inline.

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)

# Only fire on Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Detect: git push or gh pr create
ACTION=""
case "$COMMAND" in
  *"gh pr create"*) ACTION="pr_create" ;;
  *"git push"*)     ACTION="push" ;;
  *) exit 0 ;;
esac

# Skip if command failed
TOOL_ERROR=$(echo "$INPUT" | jq -r '.tool_result.stderr // empty')
TOOL_STDOUT=$(echo "$INPUT" | jq -r '.tool_result.stdout // empty')

if [ "$ACTION" = "push" ]; then
  # git push errors go to stderr; check for rejection
  if echo "$TOOL_ERROR" | grep -qi "rejected\|failed to push\|error:"; then
    exit 0
  fi
fi

if [ "$ACTION" = "pr_create" ]; then
  # gh pr create outputs the PR URL on success
  if [ -z "$TOOL_STDOUT" ] || echo "$TOOL_ERROR" | grep -qi "error\|failed"; then
    exit 0
  fi
fi

tandem_log info "post-push: detected $ACTION, prompting PR summary"

if [ "$ACTION" = "pr_create" ]; then
  MSG="A PR was just created. Update its description now: (1) Run git log --format='%B' main..HEAD (or the appropriate base branch) to read all commit bodies. (2) Condense the commit bodies into a concise, scannable PR summary. The commits contain rich epistemic records, distill them into: a brief Summary (2-3 bullets of what changed and why), Key Decisions (any non-obvious choices worth highlighting), and a Test Plan. (3) Update the PR with gh pr edit --body using the condensed summary. Do not lose information, compress it."
else
  MSG="Code was just pushed. Check if a PR exists for this branch: run gh pr view --json number,title,body 2>/dev/null. If a PR exists, read any new commit bodies since the PR was last updated (git log --format='%B' origin/main..HEAD), condense them into the existing PR description, and update with gh pr edit --body. If no PR exists, no action needed."
fi

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'

exit 0
