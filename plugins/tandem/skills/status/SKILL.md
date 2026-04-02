---
description: "Use when the user wants to check which Tandem features are installed, verify hooks are configured correctly, or see memory stats."
---

# Tandem Status

Run the status script and output the result. No preamble, no follow-up — just the script output.

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" "$(pwd)"
```

If rules files are missing, offer to re-provision by deleting `~/.tandem/.provisioned` and restarting a session (ask first — user may have intentionally disabled a feature).
