---
description: "Validate or export redacted paper reproduction memory records"
argument-hint: "--input events.jsonl --output redacted-memory.jsonl"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/memory-safety-audit.sh:*)"
  - "Read"
---

# Paper Repro Memory

Memory is disabled by default. When enabled, run `scripts/memory-safety-audit.sh` and persist only redacted event records with module, criterion, checkpoint, paper hash, and evidence lineage. Raw logs are not stored.
