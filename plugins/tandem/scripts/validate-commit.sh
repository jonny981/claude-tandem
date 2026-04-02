#!/bin/bash
# PreToolUse hook: validates git commit messages for conventional format + body presence.
# Fires on Bash tool calls. Exits 0 (allow) or 2 (deny with reason).

# Skip if running inside a worker's claude -p call
[ -n "${TANDEM_WORKER:-}" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
source "$PLUGIN_ROOT/lib/tandem.sh"

tandem_require_jq

# Read hook input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only care about Bash tool calls
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Only care about git commit commands
[[ "$COMMAND" != *"git commit"* ]] && exit 0

# Skip amend without -m (interactive amend, user is editing existing message)
if [[ "$COMMAND" == *"--amend"* ]] && [[ "$COMMAND" != *"-m"* ]]; then
  tandem_log debug "amend without -m, skipping validation"
  exit 0
fi

# Extract the full commit message
# Handle heredoc format: -m "$(cat <<'EOF' ... EOF )"
MESSAGE=""
if [[ "$COMMAND" == *"<<'EOF'"* ]] || [[ "$COMMAND" == *'<<"EOF"'* ]] || [[ "$COMMAND" == *"<<EOF"* ]]; then
  # Extract content between heredoc markers
  MESSAGE=$(echo "$COMMAND" | sed -n "/<<['\"]\\{0,1\\}EOF['\"]\\{0,1\\}/,/^[[:space:]]*EOF/{//d;p;}")
elif [[ "$COMMAND" == *'-m "'* ]]; then
  # Simple -m "message" format
  MESSAGE=$(echo "$COMMAND" | sed -n 's/.*-m "\(.*\)"/\1/p')
  if [ -z "$MESSAGE" ]; then
    MESSAGE=$(echo "$COMMAND" | sed -n 's/.*-m "//p' | sed 's/"[^"]*$//')
  fi
elif [[ "$COMMAND" == *"-m '"* ]]; then
  # Single-quoted -m 'message' format
  MESSAGE=$(echo "$COMMAND" | sed -n "s/.*-m '\\(.*\\)'/\\1/p")
  if [ -z "$MESSAGE" ]; then
    MESSAGE=$(echo "$COMMAND" | sed -n "s/.*-m '//p" | sed "s/'[^']*$//")
  fi
fi

# Can't extract message, don't block
if [ -z "$MESSAGE" ]; then
  tandem_log debug "could not extract commit message, allowing"
  exit 0
fi

# Strip \! escaping artifacts (Bash tool quirk)
MESSAGE=$(echo "$MESSAGE" | sed 's/\\!/!/g')

# Split into subject and body
SUBJECT=$(echo "$MESSAGE" | head -1)
BODY=$(echo "$MESSAGE" | tail -n +3)  # Skip subject + blank line

# ─── Validate subject: conventional commits format ───────────────────────

CC_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'
if ! echo "$SUBJECT" | grep -qE "$CC_REGEX"; then
  tandem_log info "denied: bad commit format: $SUBJECT"
  REASON="Commit subject does not follow Conventional Commits format.

Expected: <type>(<optional scope>): <description>
Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert

Your subject: ${SUBJECT}

Example: feat(auth): add OAuth2 login flow"

  jq -n --arg reason "$REASON" '{"decision": "deny", "reason": $reason}'
  exit 2
fi

# ─── Validate body: must have substantive content ────────────────────────

# Strip Co-Authored-By, Signed-off-by, and blank lines from body
SUBSTANTIVE_BODY=$(echo "$BODY" | grep -vE '^(Co-Authored-By:|Signed-off-by:|$)' | sed '/^[[:space:]]*$/d')

if [ -z "$SUBSTANTIVE_BODY" ]; then
  tandem_log info "denied: missing commit body: $SUBJECT"

  # Read progress.md for context
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  PROGRESS_CONTEXT=""
  if [ -n "$CWD" ]; then
    PROGRESS_FILE="$(tandem_progress_dir "$CWD")/progress.md"
    if [ -f "$PROGRESS_FILE" ]; then
      PROGRESS_CONTEXT=$(tail -10 "$PROGRESS_FILE")
    fi
  fi

  CONTEXT_BLOCK=""
  if [ -n "$PROGRESS_CONTEXT" ]; then
    CONTEXT_BLOCK="
Recent session context (from progress.md):
${PROGRESS_CONTEXT}
"
  fi

  REASON="Commit body is missing. Every commit is a context restoration point for future sessions.

The diff shows what changed. The body must capture what the diff cannot:
- Why does this change exist? What triggered this work?
- What was considered? Why this approach over alternatives?
- What constraints or unknowns shaped this?
- Where does this sit in the larger effort?

Write so an LLM reading git log can reconstruct the full reasoning.
${CONTEXT_BLOCK}
Rewrite the commit with a body that captures your thinking."

  jq -n --arg reason "$REASON" '{"decision": "deny", "reason": $reason}'
  exit 2
fi

# All good
tandem_log debug "commit message validated: $SUBJECT"
exit 0
