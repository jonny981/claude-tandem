---
name: progress
description: "Use when the user wants to view their current progress.md file. Also use when the user mentions 'show progress', 'current progress', 'what have we done', or '/tandem:progress'."
---

# Tandem Progress

Display the current progress.md file from the auto-memory directory.

## Steps

1. Compute the progress directory: if in a git repo, `$(git rev-parse --show-toplevel)/.claude/`; otherwise `~/.tandem/progress/$(echo "$CWD" | sed 's|/|-|g')/`.
2. Read `progress.md` from that directory.
3. If the file doesn't exist, report: "No progress.md found. It will be created when work begins."
4. If the file is template-only (Working State fields are placeholders), report: "progress.md exists but hasn't been populated yet."
5. Otherwise, display the full contents of progress.md.
