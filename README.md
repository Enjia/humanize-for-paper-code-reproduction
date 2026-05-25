# Humanize

Humanize is a paper reproduction superproject for rebuilding research code from scratch with auditable agent workflows, checkpoint reviews, and reproducible final artifacts.

It treats paper input as untrusted data, converts the paper into structured evidence, decomposes the work into modules and criteria, and drives implementation through checkpoints that must produce a runnable `reproduce.sh`, a machine-readable `results.json`, and a human-readable `reproduction-report.md`.

Humanize still contains the original RLCR loop and general planning/review utilities, but the primary design target of this repository is now paper reproduction.

## What Humanize Does

1. Ingest paper sources from PDF, Markdown, LaTeX, or plain text.
2. Sanitize input so paper text and supplementary materials never become implicit instructions.
3. Extract claims, methods, experiments, and ambiguities into an evidence map.
4. Run a `paper-decomposer` stage before implementation planning.
5. Generate module-bound criteria, artifact profiles, checkpoint graphs, and lineage-safe tasks.
6. Execute paper-scoped agents through `agent-runner` with provider, tool, workspace, timeout, and redaction metadata.
7. Gate progress through checkpoint reviews instead of trusting a single monolithic run.
8. Finish with a reproducible workspace contract and comparable results package.

## Core Pipeline

```text
paper input
  -> sanitizer
  -> evidence extractor
  -> paper-decomposer
  -> criteria + artifact profile
  -> checkpoint planner
  -> implementation/review agents
  -> reproduce.sh + results.json + reproduction-report.md
```

Important safety rule:

- Paper content is evidence, not executable instruction.

## Why This Exists

Most "paper reproduction" efforts fail for operational reasons rather than model quality:

- the paper is not decomposed before coding starts
- requirements are not bound to modules or criteria
- checkpoints are file snapshots rather than semantic gates
- outputs are not normalized into a reproducible contract
- agent memory and skill evolution happen before the execution loop is stable

Humanize is meant to make those failure modes explicit and enforceable.

## Main Concepts

### Evidence-first paper loop

- `paper input`: immutable source material plus hashes and provenance
- `evidence map`: extracted claims, methods, experiments, ambiguities
- `paper-decomposer`: module graph with `module_id`, origin, dependencies, risks, and expected artifact kinds
- `criteria`: module-bound reproduction requirements
- `artifact profile`: required and optional deliverables for a given paper type
- `checkpoint graph`: review gates with reviewer policy, acceptance rule, fallback policy, snapshots, and artifact hashes
- `agent runs`: auditable child runs with provider routing and isolation metadata

### Final package contract

Every successful workspace is expected to produce:

- `reproduce.sh`
- `results.json`
- `reproduction-report.md`

These are not optional convenience files. They are the contract that makes the workspace reviewable and rerunnable.

## Quick Start

### 1. Install the plugin

```bash
/plugin marketplace add PolyArch/humanize
/plugin marketplace add PolyArch/humanize#dev
/plugin install humanize@PolyArch
```

If you use Codex review or provider-routed subagents, install the required CLIs described in the docs.

### 2. Generate a paper reproduction plan

```bash
/humanize:gen-paper-repro-plan \
  --input paper.md \
  --output paper-repro-plan.md \
  --manifest paper-repro-plan.json \
  --workspace paper-repro/my-paper
```

This stage builds the dry-run planning package, including evidence extraction, paper decomposition, criteria, artifact profile, and checkpoint graph.

### 3. Start the paper reproduction loop

```bash
/humanize:start-paper-repro-loop paper-repro-plan.json
```

This runs the checkpoint-driven workflow in the dedicated paper workspace.

### 4. Inspect current status

```bash
/humanize:paper-repro-status --plan paper-repro-plan.json
```

Use this to inspect checkpoints, expected artifacts, and package status without reading raw state files.

## Expected Workspace Outputs

The workspace root defaults to `paper-repro/<slug>`.

Expected top-level deliverables:

- `paper-repro-plan.json`
- `reproduce.sh`
- `results.json`
- `reproduction-report.md`

Expected supporting content:

- source files and tests
- checkpoint records and reviewer verdicts
- output manifests and artifact hashes
- redacted memory records and reviewed skill candidates when those loops are enabled

Large generated outputs should live under `outputs/` and be referenced by path, hash, and summary.

## Repository Focus Areas

### Paper reproduction domain layer

- evidence schemas
- decomposition schemas
- criteria and artifact profile contracts
- checkpoint graph contracts
- result comparison and package audit scripts

### Agent runtime layer

- `agent-runner`
- provider role routing
- runtime adapters
- command guard and snapshot manager
- parent/child reviewer orchestration

### Controlled evolution layer

- memory capture, selection, consolidation, and safety audit
- skill generation, review, promotion, and safety audit

These later loops are intentionally secondary to the core paper workflow. The system should be able to reproduce a paper before it tries to evolve itself.

## Secondary Workflows

Humanize still includes the older RLCR and planning stack for non-paper tasks:

- `/humanize:gen-idea`
- `/humanize:gen-plan`
- `/humanize:refine-plan`
- `/humanize:start-rlcr-loop`
- `/humanize:ask-gemini`

Those workflows remain useful, but they are no longer the best description of the repository's purpose.

## Documentation Map

- [Paper Reproduction Overview](docs/paper-reproduction.md)
- [Paper Repro Core](docs/paper-repro-core.md)
- [Paper Decomposition](docs/paper-decomposition.md)
- [Paper Artifact Profiles](docs/paper-artifact-profiles.md)
- [Checkpoint Reviews](docs/checkpoint-reviews.md)
- [Provider Roles](docs/provider-roles.md)
- [Runtime Adapter Layer](docs/runtime-adapter-layer.md)
- [Paper Workspace Contract](docs/paper-workspace-contract.md)
- [Memory and Skills](docs/memory-and-skills.md)
- [Install for Claude Code](docs/install-for-claude.md)
- [Install for Codex](docs/install-for-codex.md)
- [Usage Guide](docs/usage.md)

## Testing

Run targeted suites when changing paper reproduction behavior:

```bash
./tests/test-paper-repro-plan.sh
./tests/test-paper-extract-and-decompose.sh
./tests/test-paper-repro-loop.sh
./tests/test-paper-repro-docs.sh
```

Run the full test suite:

```bash
./tests/run-all-tests.sh
```

The test runner now emits per-suite progress lines during long runs and still prints the final sorted summary at the end.

## Status

This repository is actively being reshaped around the paper reproduction architecture described in `paper-reproduction-superproject-plan.md`. Expect the paper domain contracts to be the primary source of truth for future changes.

## License

MIT
