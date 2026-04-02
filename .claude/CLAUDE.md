# Tandem — Claude Code Plugin

## What this is

A Claude Code plugin with two features: Recall (memory pipeline) and Commit (structured epistemic records). Ships as shell scripts + SKILL.md files — no Node, no Python, no background processes.

The memory pipeline: progress.md (session state) → commit body (permanent epistemic record) → MEMORY.md (project memory) → CLAUDE.md (permanent rules). Commits are the compaction boundary. Commit history is mined for recurring patterns to promote as rules.

## Core ethos: enhance, never replace

Claude Code already has auto-memory, MEMORY.md, context compaction, and a hook system. Tandem fills gaps in the native systems — it never builds parallel infrastructure. If Claude Code ships a native version of something Tandem does, Tandem should get out of the way. Every feature should trace back to: "Claude Code doesn't do X natively, so we add it using Claude Code's own conventions."

## Architecture constraints

- **Shell scripts only** — all scripts in `scripts/` are bash. No runtime dependencies beyond `jq` and `claude` CLI (or `curl` for URL backends).
- **Shared library** — `lib/tandem.sh` provides `tandem_log`, `tandem_print`, `tandem_header`, `tandem_progress_dir`, `tandem_memory_dir`, `tandem_require_jq`, `tandem_require_llm`, `tandem_llm_call`. Source at top of every script.
- **Silent logging** — all diagnostics go to `~/.tandem/logs/tandem.log`. Never write to stderr from hook scripts. Use `tandem_log <level> <message>` (levels: error, warn, info, debug; threshold: `TANDEM_LOG_LEVEL` env var, default info).
- **Branded output** — all user-facing output uses `tandem_print "message"` which outputs `tandem ~ message`. No ANSI in hooks (stdout becomes plain-text system messages). `status.sh` (skill, runs in terminal) may use ANSI.
- **`${CLAUDE_PLUGIN_ROOT}`** — all paths in `hooks/hooks.json` use this env var. Scripts that need plugin-relative paths resolve it via `CLAUDE_PLUGIN_ROOT` with a fallback to `$(dirname "$(dirname "$0")")`.
- **Progress directory (repo-scoped)** — progress.md lives at `<git-root>/.claude/progress.md`, co-located with project CLAUDE.md. Computed by `tandem_progress_dir()` in `lib/tandem.sh`. Falls back to `~/.tandem/progress/<cwd-slug>/progress.md` for non-git directories. Session-start.sh auto-migrates progress.md from the old auto-memory location and ensures `.claude/.gitignore` contains `progress.md`.
- **Auto-memory directory (CWD-scoped)** — MEMORY.md lives at `~/.claude/projects/$(echo "$CWD" | sed 's|/|-|g')/memory/`. This matches Claude Code's native convention. Computed by `tandem_memory_dir()` in `lib/tandem.sh`. Only `~/.tandem/memory/global.md` is shared (metadata-only session recaps). CWD that is not a git root triggers a startup warning since memory may not be project-scoped.
- **Minimal repo files** — Tandem creates only `.claude/progress.md` (gitignored) inside user repositories. All other data goes to `~/.claude/` (rules, memory) or `~/.tandem/` (state, logs).
- **Built to be forked** — Tandem is open source and designed for customisation. `lib/tandem.sh` is a shared foundation that community scripts can source. Skills, hooks, and rules are modular.
- **PreToolUse hook (Bash)** — `validate-commit.sh` enforces conventional commit format + body presence on all git commits. Sources `lib/tandem.sh`. 5s timeout.
- **Stop hook** — `reflect-progress.sh` prompts Claude to reflect on whether the work just completed warrants a progress.md entry. Creates progress.md if missing. Only fires on `end_turn` stops (not tool use or interruptions). No LLM call. 5s timeout.
- **PostToolUse hook** — `post-commit.sh` detects successful git commits and outputs a `systemMessage` instructing Claude to run the compaction pipeline inline: merge progress.md into MEMORY.md, mine recent git log for recurring patterns, promote to CLAUDE.md. No background process, no LLM API call. 5s timeout.
- **PostToolUse hook (Bash, push/PR)** — `post-push.sh` detects `git push` and `gh pr create`. On PR creation, prompts Claude to condense commit bodies into a scannable PR summary. On push with existing PR, prompts Claude to update the PR description with new commits. 5s timeout.
- **PostToolUse hook (ExitPlanMode)** — inline echo command outputs a `systemMessage` reminding Claude to update progress.md Working State after exiting plan mode. Planning is progress: decisions, approach choices, and next steps must be captured even if implementation is deferred.
- **UserPromptSubmit hook** — `check-progress.sh` outputs a brief status line (project, memory/progress ages, modified files) on every prompt. Status only, no nudging. Reflection and progress.md creation are handled by the Stop hook. 5s timeout.
- **SessionEnd hook** — sync, lightweight. Prints session summary, updates recurrence.json with themes from MEMORY.md (pure jq, no LLM), updates global.md cross-project log, deregisters session. No background workers.
- **PreCompact hook** — captures current state snapshot + progress safety net before compaction. Skips the LLM call entirely when structured Working State markers exist in progress.md and progress is fresh. Falls back to LLM extraction when markers are absent or progress is stale (>2 min).
- **TaskCompleted hook** — async reflection trigger. Accumulates completed task subjects in `~/.tandem/state/completed-tasks.jsonl`, then asks Claude to evaluate whether progress.md needs updating based on accumulated tasks since the last write. Strong nudge if progress.md is missing or template-only.
- **Commit skill** — `/tandem:commit` orchestrates structured commit authoring. Gates on progress.md (refuses if empty). References `tandem-commits.md` for format conventions (doesn't embed format inline). Frames the commit body as the primary, permanent epistemic record.
- **Swappable LLM backend** — all LLM calls go through `tandem_llm_call()` in `lib/tandem.sh`. Default: `claude -p` with haiku. Set `TANDEM_LLM_BACKEND` to an OpenAI-compatible URL for zero-cost local inference. Config lives in `~/.tandem/.env`.
- **`TANDEM_WORKER` guard** — all hook scripts exit early when `TANDEM_WORKER` is set in the environment. This prevents recursive hook firing. Heredocs in prompts must use unquoted delimiters (`<<EOF` not `<<'EOF'`) because `/bin/bash` 3.2 (macOS default) cannot parse apostrophes inside single-quoted heredocs in command substitutions.
- **Rules files** — provisioned to `~/.claude/rules/tandem-*.md` by `session-start.sh`. Install = copy, uninstall = delete. Never patch user's CLAUDE.md. Includes `tandem-commits.md` (structured commit body conventions with section headers) and `tandem-recall.md` (memory pipeline). When editing source rules in `plugins/tandem/rules/`, also update the provisioned copy at `~/.claude/rules/` so changes take effect in the current session.
- **Plugin manifest** — `.claude-plugin/plugin.json` must NOT include a `"hooks"` field. The plugin system auto-discovers `hooks/hooks.json` at the standard path. Adding it explicitly causes a "Duplicate hooks file" error.
- **Skill naming** — SKILL.md frontmatter uses short `name` (e.g., `commit`), no prefix. The plugin system adds `tandem:` automatically.
- **Statusline** — `scripts/statusline.sh` is copied to `~/.tandem/bin/statusline.sh` on first run. Session-start.sh idempotently sets `statusLine` in `~/.claude/settings.json` to point at it, and keeps the script in sync with the plugin source on upgrades.
- **Legacy stubs** — when removing hook scripts, leave a stub (no-op or `exec` redirect) because hooks.json is snapshotted at session start. Active sessions will still call the old script path until restart. Remove stubs after one release cycle.

## Build conventions

- Hook definitions live in `hooks/hooks.json`, not in individual scripts
- SessionStart fires on `startup|resume|compact` — fully idempotent, handles post-compaction state recovery
- SessionEnd is lightweight sync: session summary, recurrence.json update (jq), global.md update, deregister. No background workers, no LLM calls.
- Compaction is triggered by the post-commit hook's `systemMessage`, handled inline by Claude with full session context. Higher quality than background haiku calls.
- PreCompact writes ephemeral `## Pre-compaction State` to progress.md — consumed by SessionStart, never reaches SessionEnd. Prefers structured Working State markers when available (deterministic, no LLM).
- Memory compaction uses three priority tiers: [P1] permanent (architecture, preferences), [P2] active (current state, recent decisions), [P3] ephemeral (debugging, routine). Temporal annotations (observed: YYYY-MM-DD) enable evidence-based pruning.
- progress.md has two parts: a rewritable Working State section (between `<!-- working-state:start/end -->` markers) and an append-only Session Log below. Working State captures current task, approach, blockers, key files.
- TaskCompleted is async (`"async": true`) — accumulates task subjects, triggers reflection on whether to write to progress.md
- Scripts exit 0 on all paths — hook failures should be silent to the user
- Scripts exit early when preconditions aren't met (no progress.md = no action)
- Atomic writes: write to temp file, then `mv` to target

## File layout

All plugin code lives under `plugins/tandem/` in the repo root:

```
plugins/tandem/
  .claude-plugin/     Plugin manifests
  hooks/              Hook wiring (hooks.json)
  lib/                Shared library (tandem.sh)
  scripts/            All executable hook scripts
  skills/             SKILL.md files (commit, logs, recall-promote, reload, status)
  rules/              Source rules files (provisioned to ~/.claude/rules/)

Per-repo (gitignored):
<repo>/.claude/progress.md  Session progress (repo-scoped)

Runtime data (outside repo):
~/.tandem/state/            Recurrence themes, completed-tasks accumulator, state files
~/.tandem/logs/tandem.log   Unified log file (silent, never stderr)
~/.tandem/memory/global.md  Cross-project activity log (30 entries max)
~/.tandem/progress/         Fallback progress dir for non-git CWDs
```

## Testing

Uses [bats-core](https://github.com/bats-core/bats-core) with bats-support, bats-assert, and bats-file (git submodules in `test/lib/`).

```bash
make test              # run all tests (unit + integration)
make test-unit         # unit tests only
make test-integration  # integration tests only
make lint              # shellcheck
```

- HOME isolation: every test runs in a temp HOME, no real `~/.tandem/` or `~/.claude/` touched
- LLM mocking: mock `claude` CLI and `curl` on PATH, canned responses in `test/fixtures/`
- Git mocking: real git repos in temp dirs for commit tests
- CI: GitHub Actions on ubuntu-latest + macos-latest (bash 3.2 compat)
