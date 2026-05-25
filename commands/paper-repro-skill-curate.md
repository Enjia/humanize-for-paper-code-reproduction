---
description: "Audit paper reproduction candidate skills before promotion"
argument-hint: "--candidate .humanize/skills/candidates/<name> --output audit.json"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-safety-audit.sh:*)"
  - "Read"
---

# Paper Repro Skill Curate

Use `scripts/skill-safety-audit.sh` for candidate skill validation. Passing candidates still require manual promotion review; auto-promotion is disabled by default.
