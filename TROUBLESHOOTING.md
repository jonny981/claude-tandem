# Troubleshooting Guide

Common issues and solutions for the Tandem Claude Code plugin.

## Hook Not Firing

**Symptom:** Tandem features don't seem to work. No status messages, no MEMORY.md updates.

**Diagnosis:**

1. **Check hook installation:**
   ```bash
   cat ~/.claude/hooks/tandem/hooks.json
   ```
   Should show hook definitions. If file doesn't exist, hooks weren't installed.

2. **Verify plugin directory:**
   ```bash
   ls -la ~/.claude/plugins/tandem/scripts/
   ```
   Should show all hook scripts with execute permissions.

3. **Check CLAUDE_PLUGIN_ROOT:**
   ```bash
   echo $CLAUDE_PLUGIN_ROOT
   ```
   Should point to plugin directory (usually `~/.claude/plugins/tandem`).

4. **Test hook manually:**
   ```bash
   echo '{"cwd":"'$(pwd)'"}' | ~/.claude/plugins/tandem/scripts/session-start.sh
   ```
   Should output status indicators or provision messages.

**Solutions:**
- Reinstall plugin: `/plugin uninstall tandem@tandem-marketplace && /plugin install tandem@tandem-marketplace`
- Check Claude Code version (hooks require recent version)
- Review plugin installation logs in Claude Code

---

## SessionEnd Hangs

**Symptom:** Session appears to hang when exiting. Long delay before prompt returns.

**Diagnosis:**

1. **Check progress.md size:**
   ```bash
   find ~/.claude/projects -name progress.md -exec ls -lh {} \;
   ```
   Files >10KB can trigger longer processing times.

2. **Check for budget exhaustion:**
   SessionEnd uses haiku with `--max-budget-usd 0.05` per phase. If you've run many sessions in quick succession, budget may be exhausted.

3. **Review stderr output:**
   Look for error messages in terminal scrollback:
   ```
   [Tandem Recall] Warning: compaction LLM call failed
     This may be due to:
     - Network connectivity issues
     - API rate limits or budget exhaustion
     - Claude CLI configuration problems
   ```

**Solutions:**
- Wait for API rate limits to reset (typically 1 minute)
- Check network connectivity: `ping api.anthropic.com`
- Reduce progress.md size by committing more frequently
- If persistent, check Claude CLI config: `claude --version`

---

## Compaction Produces Garbage

**Symptom:** MEMORY.md contains refusal messages like "I cannot process this request" or becomes very short (< 5 lines).

**Diagnosis:**

1. **Check for refusal patterns:**
   ```bash
   head -1 ~/.claude/projects/*/memory/MEMORY.md
   ```
   If first line starts with "I cannot" or "I'm sorry", compaction failed.

2. **Check MEMORY.md structure:**
   ```bash
   grep '^##' ~/.claude/projects/*/memory/MEMORY.md
   ```
   Should show section headers. Empty or malformed output indicates corruption.

3. **Check for available backups:**
   ```bash
   ls -lt ~/.claude/projects/*/memory/.MEMORY.md.backup-*
   ```
   Shows timestamped backups (last 3 kept).

**Solutions:**

1. **Automatic rollback (on next session):**
   SessionStart automatically detects corrupted MEMORY.md and rolls back to latest backup.

2. **Manual rollback:**
   ```bash
   # Find your project's memory directory
   MEMORY_DIR=~/.claude/projects/-path-to-your-project/memory

   # List available backups
   ls -lt "$MEMORY_DIR"/.MEMORY.md.backup-*

   # Restore latest backup
   cp "$MEMORY_DIR"/.MEMORY.md.backup-XXXXXXXXXX "$MEMORY_DIR"/MEMORY.md
   ```

3. **Prevention:**
   - Keep progress.md entries focused and structured
   - Avoid filling progress.md with raw data dumps or very long code blocks
   - Review MEMORY.md periodically to ensure quality

---

## jq/claude CLI Errors

**Symptom:** Error messages like:
```
[Tandem] Error: jq not found
  Tandem requires jq for JSON parsing.
  Install: brew install jq (macOS) | apt install jq (Linux)
  Verify: jq --version
```

**Diagnosis:**

1. **Verify jq installation:**
   ```bash
   which jq
   jq --version
   ```
   Should show path and version (e.g., `jq-1.6`).

2. **Verify claude CLI installation:**
   ```bash
   which claude
   claude --version
   ```
   Should show path and version. Claude CLI is installed with Claude Code.

3. **Check PATH configuration:**
   ```bash
   echo $PATH
   ```
   Should include directories where jq and claude are installed.

**Solutions:**

**Install jq:**
- macOS: `brew install jq`
- Linux: `apt install jq` or `yum install jq`
- Verify: `jq --version`

**Fix claude CLI PATH:**
If `which claude` returns nothing but Claude Code is installed:
1. Find claude location:
   ```bash
   find ~ -name "claude" -type f 2>/dev/null | grep -v node_modules
   ```
2. Add to PATH in `~/.bashrc` or `~/.zshrc`:
   ```bash
   export PATH="$PATH:/path/to/claude/directory"
   ```
3. Reload shell: `source ~/.bashrc` or `source ~/.zshrc`

**Test installations:**
```bash
echo '{"test": "value"}' | jq .
claude --version
```

---

## Silent Failures

**Symptom:** Operations seem to complete but nothing happens. No errors, no output.

**Understanding Silent Failures:**
All Tandem hook scripts **exit 0** by design — hooks must never crash Claude Code. This means errors are logged to stderr but don't prevent Claude from continuing.

**Diagnosis:**

1. **Check stderr in terminal:**
   Look for `[Tandem]` messages in your shell scrollback:
   ```
   [Tandem Recall] Warning: failed to write temp file (disk full?)
   ```

2. **Check disk space:**
   ```bash
   df -h ~
   ```
   Temp file operations require available disk space.

3. **Check file permissions:**
   ```bash
   ls -la ~/.claude/projects/*/memory/
   ls -la ~/.tandem/
   ```
   Should be writable by your user.

4. **Enable verbose mode:**
   Set `TANDEM_QUIET=0` (default) to see status messages:
   ```bash
   export TANDEM_QUIET=0
   ```

**Solutions:**
- Free up disk space if needed
- Check file permissions: `chmod -R u+w ~/.claude ~/.tandem`
- Review full stderr output for specific error messages
- Test hooks manually (see "Hook Not Firing" section)

---

## Partial Session End Failures

**Symptom:** Message in progress.md:
```
## Session End Partial Failure (2026-02-11)
Recall completed: 0
```

**Meaning:**
Recall (compaction) failed during SessionEnd. Progress.md was preserved for recovery.

**Solutions:**

1. **Review the error message in stderr** (should explain why)
2. **Common causes:**
   - Network issues during LLM call
   - API rate limits or budget exhaustion
   - Corrupted JSON in recurrence.json (for Recall)
   - Very large progress.md file (>10KB)

3. **Recovery:**
   - Next SessionStart will detect the stale progress.md
   - Review and incorporate relevant context manually
   - Or just continue working — SessionEnd will retry on next session

4. **Prevention:**
   - Ensure stable network connection
   - Keep progress.md focused (don't accumulate >5KB)
   - Watch for rate limit warnings

---

## Corrupted MEMORY.md Auto-Rollback

**Symptom:** SessionStart message:
```
[Tandem] Corrupted MEMORY.md detected (3 lines, refusal pattern: 1). Rolling back to backup from 2026-02-11 14:30.
```

**Meaning:**
SessionStart detected that MEMORY.md was corrupted (too short or contains LLM refusal) and automatically restored from backup.

**This is working as intended** — automatic recovery from compaction failures.

**What to do:**
- Nothing required — rollback happened automatically
- Review the restored MEMORY.md to ensure it's current
- If recent session learnings were lost, check stale progress.md and incorporate manually

**Prevention:**
- Keep progress.md well-structured (not raw data dumps)
- Ensure stable network during SessionEnd
- Monitor for repeated corruptions (may indicate deeper issue)

---

## Orphaned or Stale Sessions

**Symptom:** `/tandem:sessions` shows sessions with dead PIDs or stale heartbeats, or the status line reports sibling sessions that don't exist.

**Diagnosis:**

1. **List sessions:**
   ```bash
   ls ~/.tandem/sessions/
   ```

2. **Check a session's state:**
   ```bash
   cat ~/.tandem/sessions/<session-id>/state.json | jq .
   ```

3. **Verify PID is alive:**
   ```bash
   kill -0 <pid>  # exit 0 = alive, exit 1 = dead
   ```

**Solutions:**

1. **Automatic cleanup:** Orphaned sessions (dead PIDs) are cleaned automatically at session start and periodically during the status line render.

2. **Manual cleanup:**
   ```bash
   /tandem:sessions clean
   ```
   This force-removes all sessions with dead PIDs.

3. **Nuclear option:**
   ```bash
   rm -rf ~/.tandem/sessions/
   ```
   Safe to do. Sessions will re-register on next start.

---

## Getting Help

If issues persist after trying these solutions:

1. **Check for updates:**
   ```bash
   /plugin update tandem
   ```

2. **Review recent changes:**
   ```bash
   git -C ~/.claude/plugins/tandem log --oneline -5
   ```

3. **Collect diagnostic info:**
   ```bash
   # Tandem version
   jq -r '.version' ~/.claude/plugins/tandem/.claude-plugin/plugin.json

   # Hook installation
   ls -la ~/.claude/hooks/tandem/

   # Recent errors
   grep -i tandem ~/.claude/logs/* 2>/dev/null | tail -20
   ```

4. **Report issue:**
   Open an issue at https://github.com/jonny981/claude-tandem with:
   - Tandem version
   - Claude Code version
   - OS and platform (macOS/Linux)
   - Diagnostic info from above
   - Stderr output showing the error

---

## Quick Reference

**Check installation:**
```bash
/tandem:status
```

**Manual hook test:**
```bash
echo '{"cwd":"'$(pwd)'"}' | ~/.claude/plugins/tandem/scripts/session-start.sh
```

**View recent activity:**
```bash
cat ~/.tandem/memory/global.md
```

**Check MEMORY.md health:**
```bash
wc -l ~/.claude/projects/*/memory/MEMORY.md
head -3 ~/.claude/projects/*/memory/MEMORY.md
```

**List available backups:**
```bash
ls -lt ~/.claude/projects/*/memory/.MEMORY.md.backup-*
```

**Suppress status output:**
```bash
export TANDEM_QUIET=1
```
