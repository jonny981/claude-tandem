<p align="center">
  <img src="assets/logo.png" alt="Tandem — companion plugin for Claude Code" width="320">
</p>

<h1 align="center">Tandem</h1>

<p align="center">
  <strong>A companion plugin for Claude Code that handles the work around the work.</strong>
</p>

<p align="center">
  <sub>Structured memory, commit reasoning, and developer learning. Pure bash, one dependency (<code>jq</code>).</sub>
</p>

```bash
claude "Let's work in Tandem"
```

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-Claude%20Code-blueviolet.svg" alt="Platform: Claude Code">
  <img src="https://img.shields.io/badge/shell-bash-orange.svg" alt="Shell: bash">
  <a href="https://github.com/jonny981/claude-tandem/actions/workflows/test.yml"><img src="https://github.com/jonny981/claude-tandem/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
</p>

---

## The problem

Claude Code has memory. MEMORY.md persists across sessions, auto-memory writes to it, CLAUDE.md is always loaded, and project rules carry forward. But there are gaps.

MEMORY.md is a flat file with a 200-line cap, no priority tiers, and no awareness of what matters most. Context compaction preserves a summary but loses the precise "where was I, what was I doing, what's next" detail needed to resume complex multi-session work. There's no session bridge, no cross-project awareness, and no mechanism to promote recurring patterns into permanent knowledge. Commit messages default to what changed, not why. And there's no structured way to surface what the developer is learning along the way.

Tandem fills these gaps through Claude Code's native hook system.

---

## Install

See [INSTALL.md](INSTALL.md) for detailed setup instructions.

**Quick start:**

```bash
# Add the marketplace
/plugin marketplace add jonny981/claude-tandem

# Install
/plugin install tandem@tandem-marketplace
```

Then start your first session:

```bash
claude "Let's work in Tandem"
```

Tandem provisions itself on first run and you'll see the startup display immediately. Run `/tandem:status` to verify everything is working.

To start a session without Tandem features, use `claude "Skip Tandem"` instead.

**Documentation:**
- [INSTALL.md](INSTALL.md): detailed installation and setup
- [CONFIGURATION.md](CONFIGURATION.md): configuration options and customization
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): common issues and solutions

---

## Features

Two features, each targeting a gap in the coding agent workflow:

<table>
  <tr>
    <td align="center" width="50%"><strong>Recall</strong><br>Structures memory</td>
    <td align="center" width="50%"><strong>Commit</strong><br>Preserves reasoning</td>
  </tr>
</table>

Each feature is independently valuable. Together, structured memory carries context forward and enriched commits capture reasoning permanently.

### Recall

Claude Code has auto-memory and context compaction. Recall adds structure on top: priority tiers, session bridging, proactive progress tracking, cross-project awareness, and safe compaction.

- **Session bridge via progress.md** maintains a two-part `progress.md` at `<git-root>/.claude/progress.md` (repo-scoped, gitignored): a rewritable Working State snapshot (current task, approach, blockers, key files) and an append-only Session Log below. Survives context compaction. Persists across sessions, with Working State carrying forward until fresh work begins.
- **Reflective progress capture** prompts Claude to evaluate whether progress.md needs updating after each response (Stop hook). Writing progress is a reflective action, not a prerequisite. If the work was trivial or a continuation with no new context, no update is needed.
- **Post-commit compaction** triggers inline memory compaction after every git commit. Claude merges progress.md into MEMORY.md, mines git log for recurring patterns, and promotes stable patterns to CLAUDE.md. Runs with full session context for higher quality than background LLM calls.
- **Priority-based memory** uses three tiers: [P1] permanent (architecture, preferences), [P2] active (current state, recent decisions), [P3] ephemeral (debugging details). Each entry carries temporal metadata (`observed: YYYY-MM-DD`) for evidence-based pruning.
- **Plan mode awareness** fires a reminder when Claude exits plan mode, prompting a progress.md update. Planning, research, and decision-making are progress worth capturing, not just code changes.
- **Session registry** tracks each session at `~/.tandem/sessions/<session-id>/` with pid, project, branch, heartbeat, and current task. Orphaned sessions (dead pid) are cleaned up automatically. Run `/tandem:sessions` to inspect.
- **Sibling awareness** discovers other active sessions on the same project at startup.
- **Pre-compaction safety net** captures the precise "where are we right now" before compaction via a PreCompact hook. When structured Working State markers exist, this is deterministic (no LLM needed).
- **Cross-project context** logs a summary to a global rolling log (`~/.tandem/memory/global.md`, 30 entries max) at session end. At session start, Claude sees recent activity from other projects.
- **Pattern promotion** surfaces recurring themes and promotes them as candidates for CLAUDE.md. Run `/tandem:recall-promote` to manually promote high-recurrence themes.
- **Task reflection** triggers async evaluation when tasks complete, asking Claude to assess whether progress.md needs updating based on accumulated completed tasks.

**What you see:** `Recalled.` at session start means the previous session's memory was compacted. `Recent work in other projects:` shows cross-repo activity. `Active sessions on this project: N sibling(s)` warns of concurrent sessions. After compaction, `Resuming. Before compaction you were: ...` restores your position. A brief status line on every prompt shows project name, memory/progress ages, and modified file count.

### Commit

Progress.md gets compacted. MEMORY.md gets rewritten. Commit messages persist forever.

Tandem treats every commit as an epistemic snapshot: the reasoning, assumptions, and knowledge state at the moment of the decision. Not just what changed, but why this approach won, what alternatives were considered, what constraints existed, and what was unknown at the time.

The commit body is the primary, permanent epistemic record, structured with four sections:

- **Why**: What process led here, including iterations and corrections along the way
- **Alternatives**: What was considered, why this approach won, what tradeoffs were accepted
- **Constraints**: Technical constraints, user preferences, assumptions, unknowns that shaped the design
- **What Next**: Where this sits in the larger effort

The session log in progress.md feeds directly into the commit body. It captures reasoning chains, corrections, and decision rationale, so the commit body has rich material to draw from.

- **Commit body enforcement** ensures every commit has a substantive body via a PreToolUse hook. Subject line follows Conventional Commits. Body captures the why, the what-else, the what-next.
- **Commit skill** (`/tandem:commit`) orchestrates structured commit authoring. Gates on progress.md, reads session context, and references the commit format conventions.

- **PR summaries** automatically condense commit bodies into scannable PR descriptions when you push or create a PR. Rich commit reasoning is distilled into a Summary, Key Decisions, and Test Plan format.
- **Feedback-aware commits** scan your auto-memory feedback files for user corrections and preferences relevant to the staged changes, weaving them into the commit body.

The result: `git log` becomes a queryable history of reasoning across AI sessions. Combined with tools that read git history, your commit log becomes a decision journal.

**What you see:** Commits without a body are blocked, with session context fed back to write from. PR descriptions are auto-generated from commit bodies.

---

## Approach

Tandem enhances Claude Code's native memory. It never replaces it.

Auto-memory, MEMORY.md, context compaction, hooks: all Claude Code native. Tandem adds structure on top. If Claude Code ships a native version of something Tandem does, Tandem gets out of the way.

**Two tracks, one system.** Context is preserved through two parallel tracks:

```
Memory track:    progress.md → MEMORY.md → CLAUDE.md
                  (session)    (project)    (permanent rules)

Git track:       commit bodies → git log
                  (epistemic record)   (permanent, queryable reasoning history)
```

The memory track manages what Claude knows. Session notes compact into working memory, working memory into project memory, proven patterns promote into permanent rules. Each stage increases signal density.

The git track captures reasoning. Every commit body snapshots the epistemic state: what was known, what constraints existed, what alternatives were considered, why this approach won. The session log in progress.md is the primary source for commit body content.

Neither track depends on the other. Together, they ensure nothing is lost to compaction.

---

## Status

```
/tandem:status
```

Reports which features are installed, hook health, and memory stats.

```
/tandem:sessions
```

Lists active sessions grouped by project, identifies orphans (dead PIDs), and offers cleanup. Use `/tandem:sessions clean` to force-clean orphans.

---

## How it works

Hook scripts, a shared library (`lib/tandem.sh`), and `jq`. No Node. No Python. No MCP servers. No daemons. No databases. No background workers.

Every feature is a lifecycle hook that runs, does its work, and exits. Compaction happens inline (triggered by the post-commit hook's systemMessage) with full session context, so Claude does the thinking, not a background haiku call. No processes persist between hooks. State files persist in `~/.tandem/` and `~/.claude/`. Nothing phones home.

| Event | Script | Purpose |
|-------|--------|---------|
| UserPromptSubmit | `check-progress.sh` | Status line with project name, memory/progress ages, modified file count |
| PreToolUse (Bash) | `validate-commit.sh` | Conventional commit format + body enforcement |
| PostToolUse (Bash) | `post-commit.sh` | Detect successful commits, trigger inline compaction pipeline |
| PostToolUse (Bash) | `post-push.sh` | Detect push/PR creation, prompt PR summary from commit bodies |
| PostToolUse (ExitPlanMode) | *(inline)* | Remind Claude to update progress.md after plan mode |
| Stop | `reflect-progress.sh` | Reflective progress capture: creates progress.md if missing, prompts evaluation after each response |
| SessionStart | `session-start.sh` | Provisioning, migration, gitignore, session registration, orphan cleanup, sibling detection, post-compaction state recovery, cross-project context |
| SessionEnd | `session-end.sh` | Session summary, recurrence.json update, global.md update, session deregistration |
| PreCompact | `pre-compact.sh` | Current state snapshot + progress safety net |
| TaskCompleted | `task-completed.sh` | Async reflection trigger: accumulate completed tasks, evaluate whether progress.md needs updating |

Dependencies: `bash 3.2+` and `jq`. No `npm install`, no `pip install`, no compilation step, no container.

### LLM backend

Background LLM calls are minimal. The only hook that calls an LLM is PreCompact (when structured Working State markers are absent and progress is stale). The primary compaction pipeline runs inline, using Claude's own session context rather than a separate LLM call.

You can point Tandem's background calls at any OpenAI-compatible endpoint, useful for local models:

```bash
# ~/.tandem/.env
TANDEM_LLM_BACKEND=http://localhost:11434   # Ollama
TANDEM_LLM_MODEL=llama3.2
```

A 7-8B parameter local model works well for the lightweight admin tasks. See [CONFIGURATION.md](CONFIGURATION.md) for full backend options.

### Cost

Most work is done inline by Claude (the compaction pipeline triggered by post-commit), which costs nothing beyond the existing session. The only background LLM call is PreCompact, and only when structured Working State markers are absent.

Typical session cost from Tandem hooks: **< $0.01**. With a local LLM backend: **$0**.

### Memory scoping

Tandem uses two scoping strategies:

- **progress.md is repo-scoped.** Stored at `<git-root>/.claude/progress.md`, so the same file is used regardless of which subdirectory you start Claude Code from. Automatically gitignored via `.claude/.gitignore`. For non-git directories, falls back to `~/.tandem/progress/<cwd-slug>/`.
- **MEMORY.md is CWD-scoped.** Stored in Claude Code's native auto-memory directory (`~/.claude/projects/{sanitised-cwd}/memory/`), which is derived from where Claude Code was launched. Always start Claude Code from your project root for correct memory scoping.

Tandem warns at startup if the current working directory is not a git root. On first session after upgrade, progress.md is automatically migrated from the old auto-memory location to the new repo-scoped location.

### Files created

Tandem creates one file in your repository (gitignored). Everything else lives outside:

**In your repo (gitignored):**
- `<repo>/.claude/progress.md`: session progress (repo-scoped)
- `<repo>/.claude/.gitignore`: auto-managed, contains `progress.md`

**Outside your repo:**
- `~/.claude/rules/tandem-*.md`: behavioural rules (4 files: recall, display, commits, debugging)
- `~/.claude/CLAUDE.md`: injected section between `<!-- tandem:start -->` and `<!-- tandem:end -->` markers
- `~/.claude/projects/{project}/memory/.MEMORY.md.backup-*`: rolling backups (up to 3)
- `~/.tandem/sessions/<session-id>/state.json`: session registry (created at start, removed at end)
- `~/.tandem/memory/global.md`: cross-project activity log (30 entries max)
- `~/.tandem/state/stats.json`: session counters and milestones
- `~/.tandem/state/recurrence.json`: pattern recurrence tracking
- `~/.tandem/state/completed-tasks.jsonl`: accumulated task subjects (cleared on session end)
- `~/.tandem/logs/tandem.log`: structured log
- `~/.tandem/progress/`: fallback progress dir for non-git directories

---

## Configuration

All configuration is via environment variables, set in `~/.tandem/.env` (loaded on every hook invocation). Copy the sample:

```bash
cp .env.sample ~/.tandem/.env
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `TANDEM_LLM_BACKEND` | `claude` | LLM endpoint. Set to an OpenAI-compatible URL for local models. |
| `TANDEM_LLM_MODEL` | `haiku` | Model name. Required for URL backends (e.g. `llama3.2`, `mistral`). |
| `TANDEM_LLM_API_KEY` | (none) | Bearer token for remote endpoints. Not needed for local models. |
| `TANDEM_LOG_LEVEL` | `info` | Log verbosity: `error`, `warn`, `info`, `debug`. |
See [CONFIGURATION.md](CONFIGURATION.md) for advanced options and file locations.

---

## Skills

| Skill | Purpose |
|-------|---------|
| `/tandem:commit` | Structured commit authoring with the memory pipeline |
| `/tandem:status` | Check installed features, hook health, memory stats |
| `/tandem:sessions` | View active sessions, clean orphans |
| `/tandem:progress` | View current progress.md |
| `/tandem:memory` | View current MEMORY.md |
| `/tandem:logs` | Check Tandem's activity log and debug hook behavior |
| `/tandem:recall-promote` | Promote recurring themes to permanent MEMORY.md entries |
| `/tandem:reload` | Sync local source to plugin cache (for development) |

---

## Uninstall

**Remove plugin:**

```bash
/plugin uninstall tandem@tandem-marketplace
```

This removes the plugin (skills, hooks, scripts). Your data is preserved.

**Complete removal (including all data):**

1. **Remove rules files:**
   ```bash
   rm ~/.claude/rules/tandem-*.md
   ```

2. **Remove CLAUDE.md section:**
   Open `~/.claude/CLAUDE.md` and delete the section between `<!-- tandem:start -->` and `<!-- tandem:end -->` (inclusive).

3. **Remove data directories:**
   ```bash
   rm -rf ~/.tandem/
   ```

4. **Remove progress.md from repos:**
   Delete `.claude/progress.md` from any repos where Tandem was used. Also clean backups:
   ```bash
   find ~/.claude/projects -name '.MEMORY.md.backup-*' -delete
   find ~/.claude/projects -name .tandem-last-compaction -delete
   ```

**Partial disable:**

To disable individual features without full uninstall:
- **Disable Recall:** `rm ~/.claude/rules/tandem-recall.md` + remove CLAUDE.md section
- **Disable Commit:** `rm ~/.claude/rules/tandem-commits.md`

---

## License

MIT
