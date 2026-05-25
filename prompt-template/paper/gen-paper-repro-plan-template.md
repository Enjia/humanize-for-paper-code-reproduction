# Generate Paper Reproduction Plan Template

Use the evidence map plus paper decomposition to generate a checkpoint-driven paper reproduction plan. Criteria are generated after decomposition, not directly from raw extraction.

Required outputs:

- `paper-repro-plan.md`
- `paper-repro-plan.json`
- Evidence map
- Paper decomposition
- Criteria fingerprint
- Artifact profile
- Checkpoint graph
- Assumption ledger
- Agent run audit for Planner A, Planner B, Synthesizer, and checkpoint planner

The final `paper-repro-plan.json` must validate and be directly usable by `start-paper-repro-loop`.

Every implementation task must include module, criterion, and checkpoint lineage. Parent checkpoints require independent reviewer runs.
