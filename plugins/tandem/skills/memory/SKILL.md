---
name: memory
description: "Use when the user wants to view their current MEMORY.md file. Also use when the user mentions 'show memory', 'current memory', 'what do we know', or '/tandem:memory'."
---

# Tandem Memory

Display the current MEMORY.md file from the auto-memory directory.

## Steps

1. Compute the auto-memory directory: `~/.claude/projects/$(echo "$CWD" | sed 's|/|-|g')/memory/`
2. Read `MEMORY.md` from that directory.
3. If the file doesn't exist, report: "No MEMORY.md found. It will be created after the first commit compaction."
4. Otherwise, display the full contents of MEMORY.md.
