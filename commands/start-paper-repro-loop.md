---
description: "Start checkpoint-aware paper reproduction loop"
argument-hint: "paper-repro-plan.json [--state-dir .humanize/paper-repro]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-paper-repro-loop.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint-validate.sh:*)"
  - "Read"
---

# Start Paper Repro Loop

Run `scripts/setup-paper-repro-loop.sh` with the supplied `paper-repro-plan.json`.

This loop uses `loop_kind=paper_repro`. It is checkpoint-aware and must not reuse the RLCR rule that one round means the whole plan is complete.
