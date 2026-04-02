<!-- tandem v1.3.0 -->
# Tandem Display

## Session triggers

When the user starts a session with **"Let's work in Tandem"**, display the Tandem startup output and follow all Tandem rules for the session.

When the user starts with **"Skip Tandem"**, acknowledge briefly and disable all Tandem behaviour for the session: no startup display, no progress.md writing, no Recall. Hooks still run silently in the background.

## Display rules

Whenever you encounter output prefixed with `◎╵═╵◎ ~` (from Tandem hooks or system messages), display it to the user exactly as-is. Bold the `◎╵═╵◎` logo. No code block, no preamble. This applies throughout the entire session, not just the first response.

At startup, Tandem outputs a single logo header line followed by plain detail lines. Display the header with the bold logo, then the detail lines underneath with no logo.
