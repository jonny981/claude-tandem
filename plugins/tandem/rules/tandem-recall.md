<!-- tandem v2.0.0 -->
# Tandem Recall

progress.md is an append-only session log. It captures everything the committed artifacts cannot: thinking, reasoning, deliberations, explorations, corrections, constraints, what was known at the time, what shaped the approach. The pipeline depends on it: progress.md → commit body → MEMORY.md → CLAUDE.md. An empty progress.md breaks every downstream step.

**Location:** `.claude/progress.md` at the git repo root. If not in a git repo: `~/.tandem/progress/<cwd-slug>/progress.md`.

**Format:** YAML frontmatter followed by append-only entries. No structure beyond that. Write freely.

```yaml
---
framework: default
type: session-progress
depends_on: []
feeds: [MEMORY.md]
---
```

## When to write

Not every action warrants a progress entry. The bar is significance: would this reasoning be lost if you only looked at the committed artifacts?

**Write when:**
- You make a design decision (chose X over Y because of Z)
- The user corrects your approach (tried X, user said no, switched to Y)
- You explore something that shapes the work (investigated X, found Y, this means Z)
- You hit a constraint that narrows the solution space
- You finish a meaningful chunk and the "why" isn't obvious from the diff
- Planning decisions: what the plan is, what comes next, what was ruled out

**Wait when:**
- The work is trivial (typo fix, obvious change)
- You are still accumulating context (reading files, exploring)
- Nothing has happened yet that a future reader would need to understand

Let signal accumulate. One good entry after a decision is worth more than five entries narrating each file read. The commit skill gates on progress having content, so capture the thinking before you commit, not necessarily before every edit.

## What to capture

Anything that would be lost from just looking at the committed files:
- Why this approach and not another
- What alternatives were considered and rejected
- What the user asked for vs what was delivered and why
- Corrections: what was tried first, why it was wrong
- Constraints that shaped the decision (technical, user preference, time)
- Explorations: what was investigated, what was found
- Planning decisions: what the plan is, why, what comes next
- What is not yet known or assumed

Do not describe what the diff will show. Describe what the diff cannot.

## The Pipeline

Use `/tandem:commit` to commit with the full pipeline:

1. **progress.md** captures session reasoning (you write this during work)
2. **Commit body** is the permanent epistemic record (condensed from progress.md)
3. **Compact**: merge learnings from progress.md into MEMORY.md, promote stable patterns to CLAUDE.md
4. **Reset progress.md** after compaction (clear everything after frontmatter)

## MEMORY.md

When writing directly to MEMORY.md, use priority tiers:
- [P1] architectural decisions, user preferences, recurring patterns
- [P2] current project state, recent decisions
- [P3] one-off details unlikely to survive next compaction

Include `(observed: YYYY-MM-DD)` on entries to aid temporal reasoning.

## CLAUDE.md promotion

The funnel: progress.md → MEMORY.md → CLAUDE.md. Each level is less contextual and more instructional.

Proactively promote stable [P1] patterns from MEMORY.md to CLAUDE.md. Prefer instructions over observations.

**What qualifies:**
- Gotchas that burned time and should never recur
- Conventions confirmed across sessions (especially if seen in 3+ commit bodies)
- Specific commands or patterns to use or avoid
- Architectural constraints that shape how to build

**Which CLAUDE.md to target:**
- **Global** (applies across all projects) → `~/.claude/CLAUDE.md`
- **Project** (applies to this repo) → project root `CLAUDE.md`
- **Subdomain** (cohesive project area) → nested `CLAUDE.md` in that directory

When promoting, remove or downgrade the MEMORY.md entry.
