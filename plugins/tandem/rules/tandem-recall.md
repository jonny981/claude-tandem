<!-- tandem v2.0.0 -->
# Tandem Recall

progress.md is the source of truth for the memory pipeline. If it is empty, commits have no session context, memory never updates, and session knowledge is lost. The entire pipeline depends on it: progress.md → commit body → MEMORY.md → CLAUDE.md. An empty progress.md breaks every downstream step.

**Init:** Create progress.md on your first action if it does not exist. Location: `.claude/progress.md` at the git repo root. If not in a git repo, use `~/.tandem/progress/<cwd-slug>/progress.md`. Start with the frontmatter and Working State template below.

**Write reflectively, after work is done.** The Stop hook prompts you to reflect on whether progress.md needs updating. When it fires, consider: was the work significant enough to capture? Is this a new direction or a continuation? What reasoning, constraints, or unknowns shaped the approach? If the work was trivial or a continuation with no new context, skip the update. If it was substantive, write a brief, high-level entry. **Planning is progress.** Plan mode transitions, plan creation, and planning decisions all warrant entries.

## Structure

progress.md has frontmatter plus two body parts:

### Frontmatter

```yaml
---
framework: default
project: tandem
type: session-progress
target: <project-directory-name>
depends_on: []
feeds: [MEMORY.md]
---
```

### 1. Working State (rewrite as context changes)

<!-- working-state:start -->
## Working State
**Current task:** [what you're actively doing]
**Approach:** [chosen approach and why]
**Blockers:** [unresolved issues, if any]
**Key files:** [files being modified]
<!-- working-state:end -->

Rewrite this section (between the markers) when starting a new task, changing approach, resolving a blocker, entering or exiting plan mode, or completing planning work. This is a snapshot of "right now", not a log.

### 2. Session Log (append-only, below the markers)

The session log feeds directly into the commit body. Write entries that capture reasoning, not just outcomes. Each entry should include: what was done, why that approach was chosen, what constraints shaped it, and any corrections or iterations along the way. If the user corrected your approach, record what you tried first and why it was wrong. The commit body mines this log for its epistemic content.

When creating or working on a plan file, note its full path.

## The Pipeline

Commits are the compaction boundary. Use `/tandem:commit` to commit with a structured epistemic record and run the full pipeline.

1. **progress.md** captures session state (you write this reflectively after completing work)
2. **Commit body** is the permanent epistemic record (authored by the commit skill, referencing tandem-commits.md conventions)
3. **Compact**: merge relevant learnings from progress.md into MEMORY.md, mine git log for recurring patterns, promote stable patterns to CLAUDE.md
4. **Reset progress.md** after compaction (frontmatter and Working State template preserved, Session Log cleared, Working State fields reset to placeholders)

The commit skill runs steps 2-4 as a single orchestrated flow. Do not skip compaction or deferring it. Session knowledge that isn't compacted into MEMORY.md is lost at the next context compaction.

## Priority annotations

When writing directly to MEMORY.md, prefix entries:
- [P1] architectural decisions, user preferences, recurring patterns
- [P2] current project state, recent decisions
- [P3] one-off details unlikely to survive next compaction

## Dates

Include (observed: YYYY-MM-DD) on MEMORY.md entries to aid temporal reasoning during compaction.

**MEMORY.md:** Write patterns worth persisting to MEMORY.md with [P1]/[P2]/[P3] priority and (observed: YYYY-MM-DD) date.

## CLAUDE.md promotion

The data funnel flows: progress.md → MEMORY.md → CLAUDE.md. Each level is less contextual and more instructional. Commit history is the richest, most reliable evidence source for promotion: if the same decision, convention, or gotcha appears across multiple commit bodies, that is strong evidence for a permanent rule.

- **progress.md** — what is happening right now, high context, ephemeral
- **MEMORY.md** — what we have learned recently, project knowledge, compacted at each commit
- **CLAUDE.md** — permanent knowledge and instructions, biased toward directives

Proactively promote stable [P1] patterns from MEMORY.md to CLAUDE.md. Prefer instructions over observations: distill knowledge into rules, constraints, and conventions where possible.

**What qualifies:**
- Gotchas that burned time and should never recur
- Conventions confirmed across sessions (especially if seen in 3+ commit bodies)
- Specific commands or patterns to use or avoid
- Architectural constraints that shape how to build

**Which CLAUDE.md to target:**
- **Global** (applies across all projects) → `~/.claude/CLAUDE.md`
- **Project** (applies to this repo) → project root `CLAUDE.md`
- **Subdomain** (cohesive project area) → nested `CLAUDE.md` in that directory

When promoting, remove or downgrade the MEMORY.md entry. CLAUDE.md is the permanent instruction set; MEMORY.md is the working buffer.
