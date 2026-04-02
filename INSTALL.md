# Tandem Installation Guide

Tandem is a Claude Code plugin that enhances session continuity through memory management, input clarification, and learning feedback. It uses shell scripts and Claude Code's native hook system — no background processes, no Node or Python runtime dependencies.

## Prerequisites

Before installing Tandem, ensure you have:

1. **bash 4+**
   Check your version:
   ```bash
   bash --version
   ```
   macOS ships with bash 3.2 by default. Install bash 4+ via Homebrew if needed:
   ```bash
   brew install bash
   ```

2. **jq** (JSON processor)
   Install via your package manager:
   ```bash
   # macOS
   brew install jq

   # Linux (Debian/Ubuntu)
   apt install jq

   # Linux (Fedora/RHEL)
   dnf install jq
   ```

3. **claude CLI**
   Installed automatically with Claude Code. Verify:
   ```bash
   which claude
   ```

## Installation

Tandem is distributed through the Claude Code plugin marketplace:

```bash
/plugin marketplace add jonny981/claude-tandem
/plugin install tandem@tandem-marketplace
```

Claude Code will:
- Download the plugin to `~/.claude/plugins/tandem/`
- Register hooks defined in `hooks/hooks.json`
- Trigger first-run provisioning on next session start

## First-Run Provisioning

On your first session after installation, Tandem's SessionStart hook will automatically provision:

1. **Rules files** → `~/.claude/rules/`
   - `tandem-recall.md` — memory management instructions

2. **CLAUDE.md section** → `~/.claude/CLAUDE.md`
   - Adds progress.md instructions (between `<!-- tandem:start -->` and `<!-- tandem:end -->` markers)
   - If CLAUDE.md doesn't exist, creates it with just the Tandem section
   - If CLAUDE.md exists, appends the section to the end

4. **Marker file** → `~/.tandem/.provisioned`
   - Timestamp to prevent re-provisioning on subsequent runs

You should see this message on first run:
```
[Tandem] First run — provisioned rules files. Run /tandem:status to verify.
```

## Verification

After installation, verify Tandem is working:

### 1. Check Installation Status

Run the status skill:
```bash
/tandem:status
```

Expected output includes:
- Plugin version (e.g., `Tandem v1.1.0`)
- Rules files status (`✓ tandem-recall.md`)
- Hook registration status

### 2. Verify Rules Files

Check that rules were provisioned:
```bash
ls -la ~/.claude/rules/tandem-*.md
```

You should see:
- `~/.claude/rules/tandem-recall.md`

### 4. Verify CLAUDE.md Section

Check that CLAUDE.md was updated:
```bash
grep -A 3 '<!-- tandem:start' ~/.claude/CLAUDE.md
```

Expected output:
```markdown
<!-- tandem:start v1.1.0 -->
## Tandem — Session Progress
After completing significant work steps (features, fixes, decisions), append a brief note to progress.md in your auto-memory directory. Include: what was done, key decisions, outcome. One or two lines per step. Create progress.md on your first significant action if it doesn't exist. This enables memory continuity between sessions.
<!-- tandem:end -->
```

## Platform-Specific Notes

### macOS

- Uses `stat -f %m` for file modification timestamps
- Requires bash 4+ from Homebrew (native bash 3.2 won't work)
- Temp file creation uses `mktemp` (BSD variant)

### Linux

- Uses `stat -c %Y` for file modification timestamps
- Most distributions ship with bash 4+ by default
- Temp file creation uses `mktemp` (GNU variant)

### Windows / WSL

- Requires WSL (Windows Subsystem for Linux)
- Install bash 4+ and jq via your WSL distribution's package manager
- All paths are relative to WSL filesystem (`~/.claude/`, `~/.tandem/`)

## Directory Structure (Post-Installation)

After installation and first run, you'll have:

```
~/.claude/
├── CLAUDE.md                    # Updated with Tandem section
├── plugins/
│   └── tandem/                  # Plugin installation directory
│       ├── .claude-plugin/
│       │   └── plugin.json      # Plugin manifest (version 1.1.0)
│       ├── hooks/
│       │   └── hooks.json       # Hook definitions
│       ├── lib/
│       │   └── tandem.sh           # Shared library (logging, sessions, LLM)
│       ├── scripts/
│       │   ├── session-start.sh
│       │   ├── session-end.sh
│       │   ├── pre-compact.sh
│       │   ├── task-completed.sh
│       ├── skills/
│       │   ├── sessions/           # Session registry inspection
│       │   └── status/
│       ├── rules/
│       │   └── tandem-recall.md
├── rules/
│   └── tandem-recall.md         # Provisioned from plugin
└── projects/
    └── <your-project>/
        └── memory/
            └── progress.md      # Created on first significant action

~/.tandem/
├── .provisioned                 # First-run marker (timestamp)
├── sessions/                    # Session registry (ephemeral, auto-cleaned)
│   └── <session-id>/
│       └── state.json           # pid, project, branch, heartbeat, task
├── memory/
│   └── global.md                # Cross-project activity log (created on SessionEnd)
└── state/
    └── recurrence.json          # Recurrence theme tracking (created on SessionEnd)
```

## Upgrading

Tandem supports automatic rules file upgrades. When you update the plugin:

```bash
/plugin update tandem
```

On the next SessionStart, Tandem will:
- Compare version comments in installed rules (`~/.claude/rules/tandem-*.md`) with plugin source files
- Overwrite installed rules if plugin version is newer
- Update the CLAUDE.md section if version changed

This ensures your rules stay in sync with the plugin without manual intervention.

## Uninstallation

To remove Tandem:

```bash
/plugin uninstall tandem@tandem-marketplace
```

This removes the plugin directory but **does not** delete provisioned files. To fully clean up:

```bash
# Remove rules files
rm ~/.claude/rules/tandem-*.md

# Remove Tandem data
rm -rf ~/.tandem/

# Remove Tandem section from CLAUDE.md (manual edit required)
# Open ~/.claude/CLAUDE.md and delete lines between:
# <!-- tandem:start v1.1.0 --> and <!-- tandem:end -->
```

## Troubleshooting

### "jq required but not found"

Install jq via your package manager (see [Prerequisites](#prerequisites)).

### Rules files not provisioned

Check that the plugin was installed correctly:
```bash
ls ~/.claude/plugins/tandem/
```

If the directory is empty or missing, reinstall:
```bash
/plugin uninstall tandem@tandem-marketplace
/plugin install tandem@tandem-marketplace
```

### SessionStart hook not firing

Verify hooks are registered:
```bash
cat ~/.claude/plugins/tandem/hooks/hooks.json
```

Check Claude Code's hook execution logs (if available) or run the script manually:
```bash
echo '{"cwd":"'$(pwd)'"}' | ~/.claude/plugins/tandem/scripts/session-start.sh
```

### Stale progress.md warnings

This is expected if you ended a previous session abnormally (e.g., Claude Code crashed, network disconnect). Tandem preserves progress.md contents for manual review. If the stale progress is no longer relevant:

```bash
rm ~/.claude/projects/<your-sanitized-cwd>/memory/progress.md
```

### CLAUDE_PLUGIN_ROOT environment variable issues

The `session-start.sh` script uses `${CLAUDE_PLUGIN_ROOT}` with a fallback to `$(dirname "$(dirname "$0")")`. If provisioning fails, check that hooks are executing with the correct working directory:

```bash
# Test provisioning manually
CLAUDE_PLUGIN_ROOT=~/.claude/plugins/tandem \
  echo '{"cwd":"'$(pwd)'"}' | \
  ~/.claude/plugins/tandem/scripts/session-start.sh
```

## Next Steps

Once installed, Tandem works automatically in the background:

1. **Recall** — tracks progress across sessions via `progress.md`, registers sessions for concurrent awareness

For usage examples and feature details, see [README.md](./README.md).

## Support

Report issues at: https://github.com/jonny981/claude-tandem/issues
