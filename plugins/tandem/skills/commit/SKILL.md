---
name: commit
description: "Use when the user asks to commit, or says 'commit', '/commit', or '/tandem:commit'. Orchestrates structured commit authoring with the full memory pipeline."
---

# Tandem Commit

Orchestrate a structured commit and run the full memory pipeline. The commit body is the **primary, permanent epistemic record**. After the commit, progress.md is compacted into MEMORY.md and reset.

## Prerequisites

Files must already be staged (`git add`). If nothing is staged, tell the user and stop.

## Step 1: Gate on progress.md

Read `progress.md` from `.claude/progress.md` at the repo root (or `~/.tandem/progress/<slug>/` if not in a git repo).

- **If progress.md is missing or template-only** (Working State fields are still placeholders): STOP. Write your Working State first (current task, approach, blockers, key files). Then continue. A commit without session context produces a weak epistemic record.
- **If progress.md has content**: proceed.

## Step 2: Read context

1. Read progress.md (full session state)
2. Scan your auto-memory directory for `feedback_*.md` files. Read any whose description suggests relevance to the staged changes. These capture user corrections and preferences that shaped the approach, exactly the kind of context the commit body should preserve.
3. Run `git diff --cached --stat` to see what is staged
4. Run `git diff --cached` for the full diff

## Step 3: Author the commit

Write the commit following the conventions in `tandem-commits.md` (the rules file, not this skill). The rules file defines the subject format and body structure. This skill orchestrates, the rule defines format.

Key principles from the rules:
- The subject uses Conventional Commits format
- The body is the permanent epistemic record, structured with section headers
- Write for machine comprehension: explicit intent, reasoning, epistemic state
- The diff shows what changed; the body captures what the diff cannot

**Condensing progress.md into the commit body:** The session log is raw material, not the final product. Apply reasoning when distilling it:
- Include only what is relevant to the staged changes. Tangents, unrelated investigations, and dead-end explorations that didn't affect the final code should be omitted.
- Identify the coherent narrative: what problem was being solved, what iterations occurred, what the user's corrections were, what constraints shaped the final design.
- If the session covered multiple unrelated topics, only capture the thread that produced the staged changes.
- Prioritise reasoning that would be hard to reconstruct from the diff alone: the why behind a design choice, constraints that aren't visible in code, alternatives that were rejected and why.

## Step 4: Commit

Run `git commit` with the authored message. Use a HEREDOC for the message body to preserve formatting.

## Step 5: Compact memory

After the commit succeeds, run the compaction pipeline immediately. Do not defer this to a hook or skip it.

1. **Read** progress.md and MEMORY.md from your auto-memory directory.
2. **Merge** session learnings from progress.md into MEMORY.md. Follow priority tiers: [P1] permanent (architecture, preferences), [P2] active (current state, recent decisions), [P3] ephemeral (debugging details). Stay under 200 lines.
3. **Mine git history** for patterns: run `git log --format='%B' -10` and look for recurring themes, decisions, or conventions across multiple commits. If a pattern appears in 3+ commits, consider promoting it to the appropriate CLAUDE.md.
4. **Promote** any stable [P1] patterns from MEMORY.md to CLAUDE.md if warranted.
5. **Reset progress.md**: preserve frontmatter and Working State template markers, clear the Session Log. The Working State fields should be reset to placeholders.

## What NOT to do

- Do not embed commit format rules in this skill. Reference `tandem-commits.md`.
- Do not skip the progress.md gate. An empty progress.md means a weak commit body.
- Do not skip compaction. The pipeline is: progress.md → commit body → MEMORY.md → CLAUDE.md → reset progress.md. Every step matters.
