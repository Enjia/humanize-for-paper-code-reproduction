---
description: "Show paper reproduction loop status"
argument-hint: "--state .humanize/paper-repro/state.json"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/paper-repro-status.sh:*)"
  - "Read"
---

# Paper Repro Status

Use `scripts/paper-repro-status.sh` to show paper type, active checkpoint, module coverage, criteria coverage, reviewer status, unresolved assumptions, memory deltas, skill deltas, and progress.
