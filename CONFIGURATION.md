# Tandem Configuration

Tandem uses environment variables to control behavior across its features (Recall, Commit). All configuration is optional — defaults are chosen for minimal friction.

## Environment Variables

| Variable | Default | Purpose | Example |
|----------|---------|---------|---------|
| `TANDEM_LLM_BACKEND` | `claude` | LLM endpoint: `claude` or OpenAI-compatible URL | `http://localhost:11434` (Ollama) |
| `TANDEM_LLM_MODEL` | `haiku` | Model name. Required for URL backends. | `llama3.2`, `mistral` |
| `TANDEM_LLM_API_KEY` | (none) | Bearer token for remote endpoints | `sk-...` |
| `TANDEM_LOG_LEVEL` | `info` | Log verbosity: `error`, `warn`, `info`, `debug` | `debug` (verbose for troubleshooting) |
| `TANDEM_QUIET` | `0` | Suppress all Tandem status output | `1` (dogfooding mode) |
| `TANDEM_AUTO_COMMIT` | `1` | Enable/disable session-end auto-commits | `0` (disable) |

### Setting Environment Variables

**`.env` file (recommended):**

Tandem loads `~/.tandem/.env` on every hook invocation. Copy from `.env.sample`:

```bash
cp .env.sample ~/.tandem/.env
```

Edit `~/.tandem/.env` and uncomment the variables you want to change.

**Shell profile (persistent):**

Add to `~/.zshrc` or `~/.bashrc`:

## Hook Input Reference

Tandem hooks receive JSON input via stdin. Each hook reads specific fields:

### SessionStart Hook (`session-start.sh`)

**Reads:**
- `cwd` (string) — Current working directory
- `session_id` (string, optional) — Claude Code's session identifier

**Example:**
```json
{"cwd": "/Users/jonny/dev/my-project", "session_id": "abc123"}
```

**Behavior:**
- Cleans up orphaned sessions (dead PIDs) from the session registry
- Registers the current session at `~/.tandem/sessions/<session-id>/state.json`
- Detects sibling sessions (other active sessions on the same project) and reports them
- First run: provisions rules files to `~/.claude/rules/`
- Every run: checks for stale progress.md, version upgrades, CLAUDE.md section injection
- Post-compaction: displays "Resuming" state snapshot
- Computes auto-memory directory: `~/.claude/projects/$(echo "$cwd" | sed 's|/|-|g')/memory/`

### SessionEnd Hook (`session-end.sh`)

**Reads:**
- `cwd` (string) — Current working directory
- `session_id` (string, optional) — Claude Code's session identifier (for deregistration)

**Example:**
```json
{"cwd": "/Users/jonny/dev/my-project", "session_id": "abc123"}
```

**Behavior:**
- Phase 0: Checkpoint commit with descriptive subject (`claude(checkpoint): <current task>`)
- Phase 1: Calls Haiku to compact MEMORY.md (budget: $0.05)
- Phase 2: Updates global activity log (`~/.tandem/memory/global.md`)
- Deregisters the session from `~/.tandem/sessions/`
- progress.md is preserved (Working State carries forward to the next session)
- Only fires if `progress.md` exists (trivial sessions skip LLM calls)

### PreCompact Hook (`pre-compact.sh`)

**Reads:**
- `cwd` (string) — Current working directory
- `transcript_path` (string) — Path to session transcript JSONL file

**Example:**
```json
{
  "cwd": "/Users/jonny/dev/my-project",
  "transcript_path": "/tmp/claude-session-abc123.jsonl"
}
```

**Behavior:**
- Reads last 20KB of transcript
- Calls Haiku to extract current state snapshot (budget: $0.03)
- Appends `## Pre-compaction State` to progress.md (consumed by SessionStart)
- If progress.md is stale (>2 min), also extracts session progress

### TaskCompleted Hook (`task-completed.sh`)

**Reads:**
- `cwd` (string) — Current working directory
- `task_subject` (string, optional) — Completed task title

**Example:**
```json
{
  "cwd": "/Users/jonny/dev/my-project",
  "task_subject": "Add authentication middleware"
}
```

**Behavior:**
- No LLM call — just checks if progress.md is stale (>5 min)
- If stale, outputs systemMessage nudge to update progress.md
- Runs asynchronously (non-blocking)

## Hook Trigger Conditions

From `plugins/tandem/hooks/hooks.json`:

| Hook | Matcher | Timeout | Async |
|------|---------|---------|-------|
| **UserPromptSubmit** | Always | 15s | No |
| **SessionStart** | `startup\|resume\|compact` | Default | No |
| **SessionEnd** | Always | 120s | No |
| **PreCompact** | Always | 30s | No |
| **TaskCompleted** | Always | Default | Yes |

**Notes:**
- SessionStart fires on `startup` (first launch), `resume` (after idle), and `compact` (post-compaction recovery)
- TaskCompleted is async — won't block task completion if hook is slow

## File Locations

Tandem never writes to user repositories. All data goes to Claude Code's native directories:

| Path | Purpose |
|------|---------|
| `~/.claude/rules/tandem-recall.md` | Provisioned rule file (session progress guidelines) |
| `~/.claude/CLAUDE.md` | Tandem injects a `<!-- tandem:start -->` section here |
| `~/.claude/projects/<cwd-sanitized>/memory/progress.md` | Session progress log (auto-memory) |
| `~/.claude/projects/<cwd-sanitized>/memory/MEMORY.md` | Compacted memory (native Claude Code convention) |
| `~/.tandem/memory/global.md` | Cross-project activity log (30 entries max) |
| `~/.tandem/state/recurrence.json` | Recurring theme tracker |
| `~/.tandem/logs/tandem.log` | Unified activity/error log (all hooks) |
| `~/.tandem/.env` | Environment variable overrides (loaded by every hook) |
| `~/.tandem/sessions/<session-id>/state.json` | Session registry (pid, project, branch, heartbeat, task) |
| `~/.tandem/.provisioned` | First-run marker file |

**Auto-memory directory naming:**

Claude Code uses project-scoped directories. For CWD `/Users/jonny/dev/my-project`, the memory directory is:

```
~/.claude/projects/-Users-jonny-dev-my-project/memory/
```

All Tandem scripts follow this convention (see `session-start.sh:15`, `session-end.sh:14`, etc.).

## Budget Caps

Tandem uses conservative LLM budget caps to prevent runaway costs:

| Hook | Model | Budget | Purpose |
|------|-------|--------|---------|
| SessionEnd (Recall) | Haiku | $0.05 | MEMORY.md compaction |
| PreCompact | Haiku | $0.03 | State snapshot |

Total worst-case per session: **$0.08** (if all hooks fire with substantive content)

Typical session cost: **$0.03-$0.08** (PreCompact + SessionEnd)

## Logs and Debugging

**Unified log:**

All hook diagnostics write to `~/.tandem/logs/tandem.log`. Hooks never write to stderr. Format:

```
2026-02-12 10:30:45 [INFO ] [session-start] provisioned rules files
2026-02-12 10:30:46 [ERROR] [session-end] compaction failed: LLM returned empty
```

View with `/tandem:logs` or `/tandem:logs errors`. Set `TANDEM_LOG_LEVEL=debug` for verbose output.

**Memory corruption recovery:**

SessionStart detects corrupted MEMORY.md (< 5 lines, starts with refusal pattern) and rolls back to the latest backup.

Backups: `~/.claude/projects/<cwd-sanitized>/memory/.MEMORY.md.backup-<timestamp>` (last 3 kept)

## Advanced Configuration

### LLM Backend

By default, Tandem uses `claude -p` (the Claude CLI) for all background LLM calls. You can point to any OpenAI-compatible endpoint instead, useful for local models (Ollama, LM Studio, vLLM) or cheaper hosted alternatives.

**Local Ollama:**

```bash
# ~/.tandem/.env
TANDEM_LLM_BACKEND=http://localhost:11434
TANDEM_LLM_MODEL=llama3.2
```

**LM Studio:**

```bash
TANDEM_LLM_BACKEND=http://localhost:1234
TANDEM_LLM_MODEL=mistral
```

**Remote endpoint with auth:**

```bash
TANDEM_LLM_BACKEND=https://api.together.xyz
TANDEM_LLM_MODEL=meta-llama/Llama-3-8b-chat-hf
TANDEM_LLM_API_KEY=your-api-key
```

`TANDEM_LLM_MODEL` is required when using a URL backend. The model name must match what the endpoint expects.

All Tandem LLM calls are low-reasoning admin tasks (memory compaction). They do not need frontier models. A 7B-8B parameter local model works well.

### Quiet Mode (Dogfooding)

```bash
export TANDEM_QUIET=1
```

Suppresses all status indicators (`Recalled.`). Used for dogfooding to avoid self-reference loops.

## Local Development (Plugin Cache Sync)

Claude Code's plugin cache only refreshes on version bumps. For local development, you can symlink your source directory into the cache so changes are live immediately.

### Option 1: Manual sync (mid-session)

Run `/tandem:reload` to create a symlink from the cache to your source directory. Script, skill, and rule changes take effect immediately. Changes to `hooks.json` take effect on next session restart.

### Option 2: Automatic sync (on startup)

Install the sync script as a user-level SessionStart hook:

```bash
# Copy to user scripts
cp plugins/tandem/scripts/sync-local-plugins.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/sync-local-plugins.sh
```

Then add to `~/.claude/settings.json` under `hooks`:

```json
"SessionStart": [{
  "matcher": "startup",
  "hooks": [{"type": "command", "command": "$HOME/.claude/scripts/sync-local-plugins.sh"}]
}]
```

This runs on every session startup and symlinks all local directory-based marketplace plugins into the cache. It's generic and works for any local plugin, not just Tandem.

**Why user-level (not plugin-level):** User-level hooks always load from disk, never from the plugin cache. A plugin-level sync hook would itself be stale if the cache is stale.

**Why symlinks:** Script changes are instant (resolved from source at runtime). Skills and rules are instant (read on demand). `hooks.json` takes effect on next startup, but the symlink means startup always reads the latest source. Overhead is ~0ms (a readlink check vs file comparison).

## Hook Script Reference

| Script | Purpose | Link |
|--------|---------|------|
| `session-start.sh` | Session registration, orphan cleanup, sibling detection, provisioning, state recovery | [plugins/tandem/scripts/session-start.sh](/plugins/tandem/scripts/session-start.sh) |
| `session-end.sh` | Recall (compaction) + session deregistration | [plugins/tandem/scripts/session-end.sh](/plugins/tandem/scripts/session-end.sh) |
| `pre-compact.sh` | State snapshot before compaction | [plugins/tandem/scripts/pre-compact.sh](/plugins/tandem/scripts/pre-compact.sh) |
| `task-completed.sh` | Async progress.md staleness check | [plugins/tandem/scripts/task-completed.sh](/plugins/tandem/scripts/task-completed.sh) |
| `sync-local-plugins.sh` | Generic plugin cache symlink sync | [plugins/tandem/scripts/sync-local-plugins.sh](/plugins/tandem/scripts/sync-local-plugins.sh) |

## Next Steps

- **Installation:** See [INSTALL.md](INSTALL.md) for setup instructions
- **Troubleshooting:** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- **Usage:** See [README.md](README.md) for feature overview
