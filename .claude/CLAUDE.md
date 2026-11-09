# Tandem

## What this is

Session continuity for Claude Code and Codex: one append-only log per repo at `<git root>/.agents/progress.md`, kept written and read back. Three hook scripts in `plugins/tandem/scripts/`, wired in `plugins/tandem/hooks/hooks.json`:

- **`session-start.sh`** (SessionStart, every source): prints the log path and its last 150 lines.
- **`log-check.sh`** (Stop): returns `decision: block` once the log is 20 minutes stale in a session 20 minutes past its first reply. Never on a Stop-hook continuation; at most once per 20 minutes (marker file in `$TMPDIR`).
- **`pre-compact.sh`** (PreCompact): if the log is over 2 minutes old, appends a Claude Haiku summary of the last 20 KB of transcript.

## Scope

Tandem does continuity and nothing else. Version 3.0.0 removed the commit gate, memory compaction, skills, rules provisioning, status line, stats, cross-project notes and the `~/.tandem` folder. A proposed feature has to serve "the agent writes the log and reads it back" or it doesn't belong here.

## Constraints

- **Both tools install this same plugin** from GitHub (`jonny981/claude-tandem`, `tandem@tandem-marketplace`). Codex reads `.claude-plugin/marketplace.json` and `hooks/hooks.json` as they are, and sets `${CLAUDE_PLUGIN_ROOT}` for hook commands. Scripts use only input fields both send (`cwd`, `session_id`, `transcript_path`, `stop_hook_active`).
- **Reaching the model:** plain stdout on SessionStart, or `decision: block` on Stop. `systemMessage` is shown only to the user, which is why the 2.x nudges never reached the model.
- **Portable shell:** bash 3.2 (macOS `/bin/bash`) and Linux. File ages use `stat -c %Y` with a `stat -f %m` fallback.
- **Silent:** every script exits 0 and writes nothing to stderr.
- **No recursion:** the Haiku call runs with `--setting-sources ""`, `--tools ""` and `--system-prompt ""`, so it loads no hooks.
- **Plugin manifest:** `plugin.json` must not have a `hooks` field; Claude Code finds `hooks/hooks.json` itself.
- **Installed copies come from GitHub, not this folder.** An edit reaches them once it is pushed with a higher `version` in `plugin.json`. Codex also asks for a new `/hooks` review whenever a script changes. To try an edit before that: `claude --plugin-dir plugins/tandem`.

## Testing

bats-core with bats-support and bats-assert (git submodules in `test/lib/`). One file per script in `test/unit/`; `helper.bash` gives every test a temp HOME, TMPDIR and git repo. A stand-in `claude` on PATH replaces the model.

```bash
make test
make lint
```
