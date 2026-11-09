<img src="assets/logo.png" alt="Tandem" width="240">

# Tandem

Tandem keeps one append-only log per repo at `.agents/progress.md`, so a new or compacted Claude Code or Codex session picks up where the last one stopped.

- **At session start and after compaction,** the agent sees the log's latest entries.
- **When the log goes stale,** the agent is asked to add an entry.
- **Before compaction,** Claude Haiku adds an entry if the agent hasn't.

## Install

**Claude Code:**

```
/plugin marketplace add jonny981/claude-tandem
/plugin install tandem@tandem-marketplace
```

**Codex:**

```
codex plugin marketplace add jonny981/claude-tandem
codex plugin add tandem@tandem-marketplace
```

Then open `/hooks` in Codex and approve Tandem's hooks.

In both tools, add `.agents/progress.md` to your global git ignore file.

Tandem needs `bash`, `git` and `jq`, plus the `claude` CLI for the before-compaction entry.

## License

[MIT](LICENSE)
