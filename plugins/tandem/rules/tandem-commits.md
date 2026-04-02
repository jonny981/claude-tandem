<!-- tandem v2.0.0 -->
# Tandem Commit

The commit body is the **primary, permanent epistemic record**. progress.md gets compacted. MEMORY.md gets rewritten. Commit messages persist forever.

When a future LLM session reads `git log`, the commit bodies are all it has. They must be rich enough to reconstruct intent, decisions, and reasoning without any other source. A decision that looks wrong in hindsight might have been the right call given what was known at the time. The commit body preserves that context.

Use `/tandem:commit` to author structured commits with the full pipeline.

**Subject:** Conventional Commits. `<type>(<scope>): <description>`, lowercase, imperative, no period.
Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.

**Body:** The diff shows what changed. The body captures everything the diff cannot, structured with section headers:

## Why

Why does this change exist? What process led here? What request, bug, or goal triggered this work? If there were iterations (tried X, user corrected to Y), capture the full chain. The first attempt and why it was wrong is as valuable as the final answer.

## Alternatives

What was considered? Were there other approaches? Why did this one win? What tradeoffs were accepted? If there were no meaningful alternatives, omit this section.

## Constraints

What shaped this decision? Include technical constraints (e.g. "hooks are shell scripts, they cannot reason about context"), user preferences that steered the approach, assumptions being made, and things that are not yet known. Separate what we know from what we are guessing. A decision that looks wrong later might have been the right call given these constraints.

## What Next

Where does this sit in the larger effort? What came before, what comes next? If this is self-contained, omit this section.

---

Write for machine comprehension. Be explicit about intent, reasoning, and epistemic state. Capture the developer's thinking at the moment of implementation. Do not summarise the diff, the diff describes itself. Describe what the diff cannot: the why, the what-else, the what-next.

The session log in progress.md is the primary source for this content. Mine it for reasoning chains, corrections, and decision rationale. The commit body is where that reasoning becomes permanent.

This is the epistemic record. When someone asks "why is this code the way it is?" six months from now, the commit body answers with the full thought process, including the iterations, corrections, and constraints that shaped the final design. Write it so an LLM can reconstruct the full context of this session from the commit message alone.

Co-Authored-By and Signed-off-by lines are not body.
