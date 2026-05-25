# Paper Reproduction Superproject Development Plan

> Status: v2 draft for human review
>
> Scope: turn Humanize from a Claude-implements/Codex-reviews RLCR plugin into a provider-neutral, checkpoint-driven, evidence-grounded system for reproducing computational research papers from scratch.

## 1. Goals

The project should support from-scratch reproduction of computational research papers when no original code is available. It must not assume every paper is a machine learning paper. It must first treat the paper as untrusted input, extract evidence, decompose the paper into modules, generate criteria and artifact profiles, insert checkpoint gates, implement in a dedicated reproduction workspace, review by module/criterion/checkpoint lineage, and produce an auditable reproduction package.

The final system should support these user-facing flows:

- Generate a paper reproduction plan from PDF, Markdown, LaTeX, arXiv text, or plain text.
- Emit both a human-readable `paper-repro-plan.md` and a machine-readable `paper-repro-plan.json`; the JSON file is the loop's source of truth.
- Run a paper reproduction loop driven by checkpoints, not by RLCR rounds.
- Swap worker and reviewer providers, including Codex-as-worker and Claude-as-reviewer.
- Use one-reviewer child checkpoints and two-reviewer parent checkpoints.
- Preserve an immutable paper fingerprint while allowing a mutable assumption ledger and plan revision log.
- Produce a final package with code, environment specification, `reproduce.sh`, `results.json`, result comparison, and an honest reproduction report.
- Add memory and skill evolution after the checkpoint reproduction system is stable.

Architecture direction:

- Short and medium term: keep Humanize as the paper reproduction runner and absorb Hermes-style runtime design patterns.
- Do not migrate the paper reproduction system onto Hermes as the MVP framework.
- Long term: extract a provider-neutral `paper-repro-core` that contains paper reproduction semantics, while Humanize and Hermes become optional runners or adapters.
- Hermes is a runtime reference for delegation, snapshots, command guards, memory safety, skill safety, terminal backends, and session search. It is not the source of truth for paper reproduction semantics.

## 2. Non-Goals for the MVP

The MVP must not try to solve every part of the superproject at once.

Out of scope for the first implementation slice:

- Automatic skill promotion.
- Full PDF layout recovery for all papers.
- Full-scale long-running experiments by default.
- Remote parsing services by default.
- Provider support beyond Codex and Claude adapters.
- Automatic publication-quality reproduction claims without human review.
- Replatforming Humanize onto Hermes.
- Building a Hermes plugin before the Humanize paper loop and `paper-repro-core` boundaries are stable.

The MVP should produce reliable dry-run plans and checkpoint graphs before it starts writing paper reproduction code.

## 3. Core Pipeline

The paper reproduction pipeline is:

```text
paper input
  -> paper input sanitizer
  -> paper-evidence-extractor
  -> paper-decomposer
  -> criteria and artifact-profile generator
  -> checkpoint planner
  -> independent implementation planners
  -> synthesized paper-repro-plan.md and paper-repro-plan.json
  -> start-paper-repro-loop
  -> final package audit and reproduction report
```

This order is mandatory. Implementation planners must not run before paper decomposition, because later development tasks need explicit module lineage.

Rationale with references:

- PaperBench uses hierarchical rubrics to decompose a paper replication into smaller gradable tasks. See [PaperBench](https://openai.com/index/paperbench/).
- RePro extracts a paper fingerprint as a comprehensive set of accurate and atomic criteria for verification and refinement. See [RePro](https://arxiv.org/abs/2508.16671).
- PaperCoder/Paper2Code uses planning, analysis, and generation phases with specialized agents and dependency-aware generation. See [Paper2Code](https://arxiv.org/abs/2504.17192).

## 4. Key Design Principles

### 4.1 Paper text is untrusted data

PDF text, LaTeX source, supplementary text, README files from paper archives, and arXiv source must be treated as untrusted data. They may contain prompt injection, tool instructions, hidden text, malicious shell snippets, or misleading claims.

Rules:

- Paper content is passed to agents inside explicit data blocks.
- Paper content cannot override system, developer, command, hook, or skill instructions.
- Extractors must quote only short evidence spans and store hashes for longer source blocks.
- Supplementary code or archives are never executed during ingestion.
- Any suggested command inside the paper is treated as evidence to evaluate, not an instruction to run.

Files to introduce:

- `scripts/paper-input-sanitize.sh`
- `agents/paper-input-safety-reviewer.md`
- `prompt-template/paper/untrusted-input-notice.md`

Tests:

- `tests/test-paper-prompt-injection.sh`
- `tests/test-paper-input-privacy.sh`

### 4.2 Paper-type-aware artifacts

Do not copy an ML artifact checklist into all domains. Use artifact profile rule packs. LLMs classify and explain; rule packs determine required, optional, and not-applicable artifacts.

Common artifacts across computational papers:

- Source code or executable notebooks for the core method.
- Dependency and environment lock files.
- Input acquisition, generation, or fixture scripts.
- A single top-level reproduction entrypoint such as `reproduce.sh`, `runme.sh`, or a documented equivalent.
- Result extraction scripts for figures, tables, logs, and metrics.
- Machine-readable `results.json`.
- Metadata describing platform, hardware, software versions, seeds where applicable, and known nondeterminism.
- A reproduction report mapping outputs to claims, figures, tables, equations, algorithms, or experiments in the paper.

Profile rule packs:

- `profiles/ml-training.json`
- `profiles/inference-optimization.json`
- `profiles/systems.json`
- `profiles/compiler.json`
- `profiles/numerical-simulation.json`
- `profiles/data-analysis.json`
- `profiles/algorithm-experiment.json`

Profile-specific examples:

- Machine learning: dataset preparation, training or fine-tuning scripts if the paper actually trains models, evaluation scripts, checkpoint handling, seed handling, result tables, and optional pretrained weights.
- Inference optimization: benchmark harnesses, kernel or runtime configs, model inputs, profiling scripts, hardware metadata, latency/throughput/memory tables, and no training scripts unless the paper includes training-dependent claims.
- Systems and compilers: build scripts, benchmark workloads, configuration flags, hardware/OS/compiler metadata, profiling traces, and artifact notes for non-portable infrastructure.
- Numerical simulation: solver implementation, input decks, convergence tests, precision settings, solver settings, comparison to analytic or reference solutions when available.
- Data analysis or empirical study: data acquisition, cleaning, feature extraction, statistical tests, table/figure generation, and provenance records.
- Algorithm theory with experiments: reference implementation, synthetic data or benchmark instances, correctness tests, complexity probes, and figure/table reproduction scripts.

Rationale with references:

- ACM artifact badging treats artifacts broadly as software systems, scripts, input datasets, raw data, and analysis scripts rather than ML-only assets. See [ACM Artifact Review and Badging](https://www.acm.org/publications/policies/artifact-review-and-badging-current).
- ECRTS artifact evaluation asks authors to identify which paper experiments are repeatable and to reference specific figures, tables, digits, system requirements, and install/use instructions. See [ECRTS Artifact Evaluation](https://archives.ecrts.org/fileadmin/WebsitesArchiv/ecrts2025/artifact-evaluation/).
- Nature computational guidelines distinguish custom code, available software, simulations, and data-driven/ML works, with validation requirements depending on the computational setting. See [Nature computational tools reporting guidelines](https://www.nature.com/documents/Computational_tools_reporting_guidelines.pdf).
- General reproducible research guidance emphasizes pinned dependencies, isolated environments, versioned data/configs, full-pipeline instructions, and output metadata. See [Kempner Institute reproducible research handbook](https://handbook.eng.kempnerinstitute.harvard.edu/s2_swe_for_research/reproducible_research.html).

### 4.3 Evidence before implementation

Before any implementation plan is written, the system must extract a paper evidence map:

- Claims: core claims, secondary claims, ablations, limitations.
- Method: algorithms, equations, architecture, data transformations, parameters.
- Experiments: datasets, benchmarks, baselines, metrics, hardware, software, seeds, tables, figures.
- Ambiguities: underspecified details, missing environment information, unclear hyperparameters, inaccessible assets.

The evidence map must not create final reproduction criteria. It records claims, methods, experiments, and ambiguities as raw evidence. Criteria are generated only after paper decomposition, because each criterion must bind to one or more modules.

Evidence references must record:

- PDF page when available.
- Section title or number.
- Figure, table, equation, algorithm, or appendix identifier when available.
- Text span or short quoted excerpt.
- Source hash.
- Extraction confidence.

### 4.4 Paper decomposition before planning

Add `paper-decomposer` as a core front-loaded agent. It must not write implementation plans. Its job is to decompose the paper into modules with explicit origins so every later task has clear lineage. Paper-origin modules must be evidence-backed; reproduction-contract, policy, and assumption modules must cite their non-paper source.

Module types:

- `algorithm_module`: core algorithm, formula, pseudocode, theory mechanism.
- `optimization_module`: kernel, runtime, cache, parallelism, performance technique.
- `data_module`: data acquisition, preprocessing, generation, feature engineering.
- `experiment_design_module`: baselines, ablations, metrics, protocol, seeds.
- `environment_module`: hardware, OS, compiler, library, GPU, distributed setup.
- `evaluation_module`: result extraction, figure/table reproduction, tolerance comparison.
- `reporting_module`: claim mapping, failure notes, not-applicable items.
- `integration_module`: top-level workflow, CLI, `reproduce.sh`.

Example module:

```json
{
  "module_id": "ALG-001",
  "module_type": "algorithm_module",
  "origin": "paper",
  "origin_source": "CLAIM-001",
  "title": "Core routing algorithm",
  "paper_evidence": ["Sec 3.1", "Algorithm 1", "Eq. 2"],
  "depends_on": ["DATA-001"],
  "claims_supported": ["CLAIM-001"],
  "reproduction_needs": ["algorithm implementation", "correctness tests", "edge-case fixtures"],
  "expected_artifact_kinds": ["source_module", "unit_test"],
  "verification_targets": ["matches Algorithm 1 behavior", "handles edge cases from Sec 3.1"],
  "ambiguities": ["tie-breaking rule not specified"],
  "risk_level": "high"
}
```

Module origins:

- `paper`: directly grounded in paper evidence.
- `reproduction_contract`: required to make the reproduction package executable or auditable, such as `reproduce.sh` or `results.json`.
- `policy`: required by configured safety, environment, budget, data, or artifact policy.
- `assumption`: introduced because the paper is underspecified and a fallback assumption is needed.

Lineage rules:

- `paper-decomposer` can only use paper evidence, explicit reproduction contracts, and configured policy inputs; implementation guesses must be recorded as assumptions.
- Each paper-origin module must have paper evidence.
- Reproduction-contract and policy-origin modules do not need paper evidence, but must cite the contract or policy that requires them.
- Assumption-origin modules must link to an assumption ledger entry.
- Each criterion must belong to at least one module.
- Each checkpoint must cover one or more modules.
- Each implementation task must include `lineage_mode`, non-empty `module_ids`, non-empty `criterion_ids`, and `checkpoint_id`.
- `lineage_mode` must be one of `single`, `primary`, or `multi_equal`.
- `single` means the task has exactly one module and one criterion; `primary` means multiple lineages exist but one module and criterion drive the task; `multi_equal` means the task intentionally spans multiple lineages without a primary owner.
- `primary_module_id` and `primary_criterion_id` are required when `lineage_mode` is `single` or `primary`, and omitted when `lineage_mode` is `multi_equal`.
- For `single`, `module_ids` must contain exactly one ID, `criterion_ids` must contain exactly one ID, and the primary IDs must equal those unique IDs.
- For `primary`, `primary_module_id` must be present in `module_ids`, and `primary_criterion_id` must be present in `criterion_ids`.
- Reviewer verdicts must be organized by module, criterion, and checkpoint when possible. Global findings are allowed only when they explain why no specific module or criterion can be assigned.

Files to introduce:

- `agents/paper-decomposer.md`
- `schema/paper-decomposition.schema.json`
- `prompt-template/paper/paper-decomposition.md`
- `tests/test-paper-decomposition.sh`
- `tests/fixtures/paper-decomposition/*.md`

### 4.5 Immutable fingerprint, mutable execution records

The system must split immutable and mutable artifacts:

- Immutable: paper hash, input source list, extracted evidence map, paper fingerprint, decomposition modules, original criteria.
- Mutable: assumption ledger, plan revision log, checkpoint status, reviewer findings, environment findings, feasibility status.

This prevents the loop from silently rewriting the paper's meaning while still allowing practical reproduction decisions when the paper is underspecified.

### 4.6 Dedicated reproduction workspace

Paper reproduction code should not be generated inside the Humanize plugin repository by default.

Default workspace:

- `paper-repro/<paper-slug>/`

User override:

- `--workspace <path>`

Workspace path safety:

- Reject empty paths, absolute system-sensitive paths, parent traversal, shell metacharacters, and paths containing control characters.
- Reject symlink traversal in any path segment.
- Reject paths inside `.humanize/`, `.git/`, `.claude-flow/`, `.swarm/`, plugin runtime directories, or global configuration directories.
- Resolve the final path under the project root unless an explicit trusted external workspace mode is later added.

Workspace contract:

- The workspace contains the reproduction package.
- `.humanize/` remains runtime state and can stay ignored.
- Deliverable artifacts must live in the workspace, not only in ignored runtime state.
- The plan JSON and final report must record workspace path, generated files, ignored output directories, and commit/cleanup policy.

Expected workspace layout:

```text
paper-repro/<paper-slug>/
  paper-repro-plan.md
  paper-repro-plan.json
  reproduce.sh
  results.json
  reproduction-report.md
  environment/
  src/
  tests/
  scripts/
  outputs/
```

The root `results.json` is a latest-run summary and index. Each run writes its own immutable result file under `outputs/<run-id>/results.json`; the root file points to the latest run, lists prior run IDs, and summarizes the current reproduction verdict.

### 4.7 Checkpoint-aware review

Do not overload the existing RLCR round semantics. Paper reproduction requires a new checkpoint state machine.

Checkpoint types:

- Child checkpoint: one independent reviewer checks a focused substage.
- Parent checkpoint: two independent reviewers check a milestone composed of multiple child checkpoints.

Checkpoint contract fields:

- `checkpoint_id`
- `kind`: `child` or `parent`
- `covered_modules`
- `covered_criteria`
- `expected_artifacts`
- `verification_commands`
- `reviewer_count`
- `reviewer_provider_policy`
- `base_snapshot`
- `target_snapshot`
- `changed_paths`
- `artifact_hashes`
- `checkpoint_base_commit`
- `acceptance_rule`
- `open_question_policy`
- `fallback_policy`

Checkpoint files:

- `checkpoint-<id>-evidence.json`
- `checkpoint-<id>-summary.md`
- `checkpoint-<id>-reviewer-1.json`
- `checkpoint-<id>-reviewer-2.json` for parent checkpoints.
- `checkpoint-<id>-verdict.json`
- `checkpoint-<id>-next-prompt.md`

Child checkpoints verify narrow deliverables, such as parser output, data stats, benchmark smoke tests, or one reproduced table. Parent checkpoints verify milestone-level coherence, such as whether implemented modules still match the paper fingerprint and whether child-stage assumptions conflict.

### 4.8 Provider-neutral worker and reviewer roles

Refactor the current Codex-specific RLCR loop into a provider-neutral execution layer, but preserve existing RLCR defaults.

Required roles:

- `worker_provider`: the agent/tool that edits code.
- `summary_reviewer_provider`: the provider that reviews checkpoint summaries and evidence.
- `code_reviewer_provider`: the provider that reviews code diffs.
- `planner_provider`: the provider used for paper analysis and plan generation.
- `memory_provider`: the provider used for memory consolidation.
- `skill_provider`: the provider used for skill generation and review.

Each role must carry executable settings:

- `provider`
- `model`
- `effort`
- `timeout_seconds`
- `sandbox_mode`
- `write_policy`
- `network_policy`
- `workspace_root`

Planner strategies:

- `single`: one planner role.
- `dual`: two independent planners with the same provider class but separate sessions.
- `mixed`: two independent planners using different providers when available, then a synthesizer role.

Planner strategy resolution:

- `planner_strategy` is the strategy selector.
- `planner_provider` is a legacy fallback only; if `planner_strategy` is `mixed`, the router must resolve `planner_a_provider`, `planner_b_provider`, and `planner_synthesizer_provider`.
- `single` uses `planner_provider` or `planner_a_provider`.
- `dual` requires two independent planner sessions and may use the same provider with different `reviewer_run_id` or session IDs.
- `mixed` prefers different provider classes for Planner A and Planner B. If only one provider is installed, it must downgrade explicitly to `dual` and record the downgrade in the plan review trail.

Provider interface:

- `provider_run_prompt`
- `provider_review_diff`
- `provider_capabilities`
- `provider_check_dependencies`
- `provider_version`

Rules:

- Role config explicitly declares provider; model-name guessing is fallback only.
- Dependency checks are role-aware and capability-aware.
- Reviewer providers default to read-only mode.
- Worker providers may write only in the configured workspace.
- Decomposer, planner, synthesizer, reviewer, memory, and skill agents must be launched through the runtime adapter layer's `agent-runner`; they must not call provider CLIs directly.
- Existing `/humanize:start-rlcr-loop` behavior remains unchanged by default.

### 4.9 Runtime adapter layer

Add a runtime adapter layer inspired by Hermes, without taking Hermes as an MVP dependency. The adapter layer records every agent invocation as a structured run and gives the paper loop a stable execution boundary across Humanize, Codex, Claude, and future Hermes adapters.

Long-term layering:

1. `paper-repro-core`
   - Owns schemas, evidence map, decomposition, criteria, artifact profile, checkpoint graph, state transition rules, and result comparison contracts.
   - Must not invoke provider CLIs, shell commands, Hermes APIs, Codex APIs, or Claude APIs directly.
2. `humanize-paper-runner`
   - Remains the MVP entry point.
   - Owns `/humanize:gen-paper-repro-plan`, `/humanize:start-paper-repro-loop`, hooks, workspace policy, checkpoint gates, provider config, and compatibility with existing RLCR behavior.
3. `runtime-adapters/*`
   - Own provider/session execution, snapshots, command guards, terminal backends, memory safety, and skill safety.
   - May include a future `runtime-adapters/hermes` or `hermes-paper-repro-adapter` after Humanize's paper loop is reliable.

Files to introduce:

- `schema/agent-run.schema.json`
- `schema/runtime-adapter.schema.json`
- `scripts/lib/agent-runner.sh`
- `scripts/lib/runtime-adapter-common.sh`
- `scripts/lib/runtime-adapter-humanize.sh`
- `scripts/lib/snapshot-manager.sh`
- `scripts/lib/command-guard.sh`
- `scripts/lib/memory-safety-scanner.sh`
- `scripts/lib/skill-safety-scanner.sh`
- `docs/runtime-adapter-layer.md`

Required `agent-run` fields:

- `run_id`
- `role`
- `parent_run_id`
- `independence_group`
- `provider`
- `model`
- `effort`
- `tool_policy`
- `workspace_scope`
- `write_policy`
- `network_policy`
- `timeout_seconds`
- `input_artifacts`
- `output_artifacts`
- `summary_artifact`
- `redaction_status`
- `started_at`
- `ended_at`
- `exit_status`

Runtime rules:

- Every decomposer, planner, synthesizer, reviewer, memory consolidator, memory selector, skill generator, and skill reviewer invocation must create an `agent-run` record.
- Direct provider CLI calls are invalid for paper-run-scoped agents because they bypass lineage, independence, redaction, and artifact tracking.
- `agent-runner` must write each run record before execution starts and finalize it after the output artifact is validated.
- Read-only roles must receive a read-only workspace view or provider sandbox policy.
- Worker roles may write only inside the configured reproduction workspace.
- Paper input text remains untrusted data even when passed through a runtime adapter.

Review independence rules:

- Parent checkpoint reviewers must have distinct `run_id` values.
- Parent checkpoint reviewer outputs must come from separate prompt invocations; copying one output into two verdict files is invalid.
- `independence_group` binds runs that are expected to be independent for a gate, such as the two parent checkpoint reviewers or two independent implementation planners.
- `reviewer_provider_policy` decides whether independent runs must use different providers, different models, or only different sessions.
- A synthesizer may summarize, compare, and adjudicate reviewer findings, but must preserve original reviewer artifacts and cannot overwrite them.

Hermes-inspired runtime patterns to absorb:

- Isolated subagent context with parent/child run identity.
- Restricted tool policy per role.
- Bounded parallel batch execution for independent planners and reviewers.
- Shadow snapshot or equivalent `base_snapshot` / `target_snapshot` capture without polluting the reproduction workspace.
- Command guard before dangerous shell execution.
- Memory and skill safety scanners before persistence or promotion.
- Optional terminal backend interface for local, Docker, SSH, Modal, Singularity, or Daytona-style execution after MVP.

Do not import Hermes wholesale for the MVP. Hermes includes messaging gateways, TUI, cron, RL environments, plugin systems, and broad agent OS behavior that are outside the paper reproduction critical path. The paper reproduction domain model must remain owned by `paper-repro-core`.

### 4.10 Budget, feasibility, and policy gates

Budget profiles must be executable constraints, not labels.

Budget fields:

- maximum wall time.
- maximum download size.
- whether network is allowed.
- whether GPU is allowed.
- whether full datasets are allowed.
- whether long training, sweep, or profiling runs are allowed.
- smoke-only vs standard vs full reproduction mode.

Feasibility taxonomy:

- `fully_reproducible`
- `approximate`
- `smoke_only`
- `blocked_by_data`
- `blocked_by_hardware`
- `blocked_by_license`
- `underspecified`

Policy gates:

- Data/license/privacy gate for datasets, model weights, commercial solvers, IRB/PII data, and restricted benchmarks.
- Environment gate for Docker, Conda, uv/pip, Nix, or devcontainer strategy.
- Baseline policy for when to implement baselines, when to compare against reported numbers, and when to mark a baseline as not reproducible.
- Hyperparameter search policy for full sweeps, reduced sweeps, fixed paper values, and smoke-mode approximations.

### 4.11 Reproduction entrypoint and result contract

Every final package should expose a stable top-level CLI:

```bash
./reproduce.sh --smoke
./reproduce.sh --full
./reproduce.sh --offline
./reproduce.sh --skip-download
./reproduce.sh --output-dir outputs/run-001
./reproduce.sh --seed 123
./reproduce.sh --clean
```

`results.json` must be machine-readable and support:

- exact match.
- numeric tolerance.
- trend match.
- qualitative or structural match.
- missing output.
- unit mismatch.

Profile-specific comparison rules:

- Benchmark papers record warmup, repeat count, outlier policy, confidence interval, hardware disclosure, and profiler settings.
- Numerical/simulation papers record precision, tolerance, solver settings, convergence tests, and reference comparisons.
- Data-analysis papers record data provenance, cleaning pipeline, statistical tests, and figure/table regeneration.
- Algorithm-experiment papers record correctness tests and complexity probes.

## 5. Agent Evolution, Memory, and Skill System

Memory and skill evolution are required for the final superproject, but they are not MVP prerequisites for the checkpoint loop. Implement them after the paper loop and final package audit are reliable.

### 5.1 Memory model

Add a structured memory system with three layers:

- Episodic memory: per-checkpoint events, failed attempts, review findings, environment issues, experiment outcomes.
- Semantic memory: distilled facts about paper types, reproduction patterns, domain-specific gotchas, validated assumptions.
- Procedural memory: reusable workflows, scripts, command recipes, and skill candidates.

Memory lifecycle:

1. Inspect checkpoint summaries, reviewer comments, command logs, test outputs, and final reports.
2. Redact secrets before any memory event is persisted.
3. Persist only redacted event records; unredacted raw logs are not copied into memory storage.
4. Extract candidate memories after each checkpoint.
5. Validate memories against evidence and current repository state.
6. Merge duplicates and update related memories.
7. Index memories with tags, module IDs, criteria IDs, checkpoint IDs, paper type, files, commands, and outcomes.
8. Retrieve relevant memories before planning, implementation, review, and skill generation.

Files to introduce:

- `.humanize/memory/events.jsonl`
- `.humanize/memory/memories.jsonl`
- `.humanize/memory/links.jsonl`
- `.humanize/memory/index.json`
- `scripts/memory-capture.sh`
- `scripts/memory-consolidate.sh`
- `scripts/memory-select.sh`
- `agents/memory-consolidator.md`
- `agents/memory-selector.md`

Rationale with references:

- Reflexion uses verbal reflection and episodic memory to improve future trials without weight updates. See [Reflexion](https://arxiv.org/abs/2303.11366).
- Generative Agents combine observation, planning, and reflection; their ablation indicates these components matter. See [Generative Agents](https://arxiv.org/abs/2304.03442).
- A-MEM dynamically organizes memories with structured attributes, links, and memory evolution. See [A-MEM](https://arxiv.org/abs/2502.12110).
- Letta/MemGPT-style systems separate active memory from archival memory and let agents maintain memory blocks. See [Letta memory architecture](https://docs.letta.com/guides/agents/architectures/memgpt).

### 5.2 Skill lifecycle

Automatic skill generation, update, and usage must be gated.

Skill states:

- `candidate`: proposed from repeated memory patterns or checkpoint failures.
- `validated`: passes structure, safety, and utility checks.
- `active`: available to agents.
- `deprecated`: replaced or shown harmful.
- `blocked`: rejected due to safety, irrelevance, or failed validation.

Skill lifecycle:

1. Detect repeated patterns from memory, such as benchmark harness setup for inference optimization papers.
2. Generate a candidate skill package with `SKILL.md`, optional scripts, examples, and validation commands.
3. Store candidates under `.humanize/skills/candidates/` by default.
4. Run a skill reviewer agent to check scope, trigger description, safety, and context footprint.
5. Run sample tasks or fixture-based tests to validate the skill.
6. Promote to `.claude/skills/` only after explicit validation and optional human approval.
7. Retrieve and apply active skills before relevant tasks.
8. Update or deprecate skills when they cause failures, become redundant, or get superseded.

Files to introduce:

- `.humanize/skills/registry.json`
- `.humanize/skills/candidates/`
- `scripts/skill-candidate-generate.sh`
- `scripts/skill-validate.sh`
- `scripts/skill-promote.sh`
- `scripts/skill-select.sh`
- `agents/skill-generator.md`
- `agents/skill-reviewer.md`
- `agents/skill-curator.md`

Rationale with references:

- Voyager shows an automatic curriculum, an ever-growing executable skill library, and iterative prompting with feedback and self-verification. See [Voyager](https://arxiv.org/abs/2305.16291).
- SkillX proposes multi-level skills, iterative refinement, and exploratory expansion from trajectories. See [SkillX](https://arxiv.org/abs/2604.04804).
- CoEvoSkills argues that skills are multi-file artifacts and proposes generator/verifier co-evolution. See [CoEvoSkills](https://arxiv.org/abs/2604.01687).
- Claude Code skills are structured `SKILL.md` packages with optional scripts and supporting files, and support project-local and plugin-level skills. See [Claude Code skills](https://code.claude.com/docs/en/skills).

### 5.3 Skill safety and governance

Automatic skill evolution creates supply-chain risk. The system must treat skills as operational code, not passive notes.

Rules:

- Generated skills default to `candidate`, not active.
- Skills with side effects must be user-invocable only unless explicitly trusted.
- Skill descriptions must be narrow and non-adversarial.
- Skill scripts must be path-safe, non-destructive by default, and covered by validation commands.
- Promotion requires independent reviewer approval.
- Skills must record provenance: source memories, source checkpoint, authoring agent, reviewer, validation commands, and timestamp.
- Skills that modify loop behavior, credentials, network access, or shell execution require human approval.

Rationale with references:

- A 2026 study on `SKILL.md` attacks shows that skill metadata and instructions affect discovery, selection, and governance, creating semantic supply-chain risk. See [Under the Hood of SKILL.md](https://arxiv.org/abs/2605.11418).
- This project-specific design adds governance because automatic skill writing is explicitly required.

## 6. Proposed User Commands

Add these commands:

- `/humanize:gen-paper-repro-plan --input paper.pdf --output paper-repro-plan.md --manifest paper-repro-plan.json [--workspace paper-repro/<slug>]`
- `/humanize:start-paper-repro-loop paper-repro-plan.json`
- `/humanize:paper-repro-status`
- `/humanize:paper-repro-memory`
- `/humanize:paper-repro-skill-curate`

### `gen-paper-repro-plan`

Inputs:

- PDF, Markdown, LaTeX, arXiv URL text export, or plain text.
- Optional local supplementary files.
- Optional target domain override, such as `--paper-type inference-optimization`.
- Optional budget profile, such as `--budget smoke`, `--budget standard`, or `--budget full`.
- Optional workspace path.
- Optional from-scratch policy.

From-scratch policy:

- `pure`: ignore official or third-party code except as existence metadata.
- `reference-only`: inspect but do not copy external implementations.
- `compare`: use existing implementations only for comparison and validation.

Outputs:

- `paper-repro-plan.md`
- `paper-repro-plan.json`
- Evidence map.
- Paper decomposition.
- Criteria fingerprint.
- Artifact profile.
- Checkpoint graph.
- Assumption ledger.
- Review trail from Planner A, Planner B, Synthesizer C, and checkpoint planner.

### `start-paper-repro-loop`

Starts a checkpoint-aware loop over `paper-repro-plan.json`. It must not reuse the RLCR rule that one round means the whole plan is complete. It should use `loop_kind=paper_repro` or a dedicated paper stop hook.

### `paper-repro-status`

Shows current paper type, active checkpoint, module coverage, criteria coverage, reviewer status, unresolved assumptions, memory deltas, skill deltas, and reproduction progress.

### `paper-repro-memory`

Lists, validates, consolidates, or exports memories.

### `paper-repro-skill-curate`

Shows candidate skills, validation results, active skills, deprecated skills, and promotion decisions.

## 7. Data Schemas

Create JSON Schema files under `schema/`.

Required schemas:

- `schema/paper-input.schema.json`
- `schema/paper-evidence-map.schema.json`
- `schema/paper-decomposition.schema.json`
- `schema/reproduction-criteria.schema.json`
- `schema/artifact-profile.schema.json`
- `schema/checkpoint-graph.schema.json`
- `schema/reproduction-plan.schema.json`
- `schema/agent-run.schema.json`
- `schema/runtime-adapter.schema.json`
- `schema/provider-role.schema.json`
- `schema/reviewer-verdict.schema.json`
- `schema/memory-entry.schema.json`
- `schema/skill-entry.schema.json`

Paper-run-scoped schemas should include:

- `schema_version`
- `created_at`
- `paper_hash`
- `input_sources`
- `budget_profile`
- `unsupported_items`
- `risk_level`
- `privacy_mode`

Applies to:

- `schema/paper-input.schema.json`
- `schema/paper-evidence-map.schema.json`
- `schema/paper-decomposition.schema.json`
- `schema/reproduction-criteria.schema.json`
- `schema/artifact-profile.schema.json`
- `schema/checkpoint-graph.schema.json`
- `schema/reproduction-plan.schema.json`
- `schema/agent-run.schema.json`

Provider, memory registry, skill registry, and other global schemas should include their own scope metadata instead of paper-specific fields.

### Reproduction plan manifest

`paper-repro-plan.json` is the machine source of truth. Markdown files are human-facing projections.

Required manifest sections:

- `paper`
- `workspace`
- `input_sources`
- `safety`
- `budget`
- `feasibility`
- `evidence_map`
- `decomposition`
- `criteria`
- `artifact_profile`
- `assumption_ledger`
- `checkpoint_graph`
- `tasks`
- `provider_roles`
- `agent_runs`
- `review_policy`
- `final_package_contract`

### Paper module

Fields:

- `module_id`
- `module_type`
- `origin`
- `origin_source`
- `title`
- `paper_evidence`
- `depends_on`
- `claims_supported`
- `reproduction_needs`
- `expected_artifact_kinds`
- `verification_targets`
- `ambiguities`
- `risk_level`

`paper_evidence` is required when `origin` is `paper`. For `reproduction_contract`, `policy`, or `assumption` modules, `origin_source` must cite the contract, policy, or assumption ledger entry that justifies the module.

### Reproduction criterion

Fields:

- `criterion_id`
- `module_ids`
- `type`: `claim`, `method`, `data`, `metric`, `experiment`, `environment`, `artifact`, `report`
- `paper_evidence`
- `expected_artifacts`
- `expected_artifact_kinds`
- `expected_outputs`
- `verification_method`
- `tolerance`
- `status`
- `blocking`
- `open_questions`

### Artifact profile

Fields:

- `paper_types`
- `profile_rule_packs`
- `required_artifacts`
- `optional_artifacts`
- `not_applicable_artifacts`
- `rationale`
- `source_criteria`

### Checkpoint

Fields:

- `checkpoint_id`
- `kind`
- `title`
- `depends_on`
- `covered_modules`
- `covered_criteria`
- `expected_artifacts`
- `verification_commands`
- `reviewer_count`
- `reviewer_run_ids`
- `reviewer_provider_policy`
- `base_snapshot`
- `target_snapshot`
- `changed_paths`
- `artifact_hashes`
- `checkpoint_base_commit`
- `acceptance_rule`
- `open_question_policy`
- `fallback_policy`
- `failure_escalation`

### Implementation task

Fields:

- `task_id`
- `title`
- `lineage_mode`
- `primary_module_id`
- `module_ids`
- `primary_criterion_id`
- `criterion_ids`
- `checkpoint_id`
- `expected_files`
- `commands`
- `risk_level`
- `budget_impact`

### Reviewer verdict

Fields:

- `reviewer_id`
- `reviewer_run_id`
- `checkpoint_id`
- `module_findings`
- `criterion_findings`
- `global_findings`
- `artifact_findings`
- `command_findings`
- `reasonable_findings`
- `conflicting_findings`
- `required_actions`
- `verdict`: `pass`, `pass_with_notes`, `fail`, `blocked`

### Agent run

Fields:

- `run_id`
- `role`
- `parent_run_id`
- `independence_group`
- `provider`
- `model`
- `effort`
- `tool_policy`
- `workspace_scope`
- `write_policy`
- `network_policy`
- `timeout_seconds`
- `input_artifacts`
- `output_artifacts`
- `summary_artifact`
- `redaction_status`
- `started_at`
- `ended_at`
- `exit_status`

Rules:

- Paper-run-scoped agent executions must be represented by this schema.
- `role` must identify the logical paper reproduction role, such as `paper_decomposer`, `planner_a`, `planner_b`, `synthesizer`, `checkpoint_planner`, `checkpoint_reviewer`, `memory_consolidator`, or `skill_reviewer`.
- `independence_group` is required when a gate depends on independent runs.
- `input_artifacts`, `output_artifacts`, and `summary_artifact` must reference files or manifest entries, not opaque transcript text.
- `redaction_status` must be `not_needed`, `redacted`, or `blocked`.
- Failed or blocked runs remain in the manifest; they are not deleted from the audit trail.

## 8. Implementation Architecture

### 8.1 Provider adapter layer

Create:

- `scripts/lib/provider-router.sh`
- `scripts/lib/provider-codex.sh`
- `scripts/lib/provider-claude.sh`
- `scripts/lib/provider-common.sh`

Responsibilities:

- Resolve provider from explicit role config, falling back to model-name detection only when provider is absent.
- Check provider binary dependencies conditionally.
- Report provider capabilities.
- Map effort levels.
- Run prompt-based execution.
- Run diff/code review when supported.
- Normalize outputs into a common reviewer verdict format.

Modify:

- `scripts/setup-rlcr-loop.sh`
- `hooks/loop-codex-stop-hook.sh`
- `scripts/ask-codex.sh`
- `config/default_config.json`
- `tests/test-model-router.sh`

Acceptance criteria:

- Existing RLCR behavior remains unchanged by default.
- Setting worker/reviewer providers changes only the selected execution adapter.
- Missing provider dependency errors mention the configured role and provider.
- Claude reviewer configuration does not require Codex to be installed.
- Paper-run-scoped agent execution goes through `agent-runner`, not direct provider CLI calls.

### 8.2 Runtime adapter and agent-runner

Create:

- `scripts/lib/agent-runner.sh`
- `scripts/lib/runtime-adapter-common.sh`
- `scripts/lib/runtime-adapter-humanize.sh`
- `scripts/lib/snapshot-manager.sh`
- `scripts/lib/command-guard.sh`
- `scripts/lib/memory-safety-scanner.sh`
- `scripts/lib/skill-safety-scanner.sh`
- `schema/agent-run.schema.json`
- `schema/runtime-adapter.schema.json`
- `tests/test-agent-runner.sh`
- `tests/test-runtime-adapter-layer.sh`
- `tests/test-agent-run-independence.sh`
- `tests/test-snapshot-manager.sh`
- `docs/runtime-adapter-layer.md`

Responsibilities:

- Create an `agent-run` record before every paper-run-scoped agent invocation.
- Launch decomposer, planner, synthesizer, reviewer, memory, and skill agents through a single audited entrypoint.
- Resolve provider role config into provider adapter calls.
- Enforce role-specific tool, write, network, timeout, and workspace policies.
- Capture `input_artifacts`, `output_artifacts`, `summary_artifact`, exit status, and redaction status.
- Provide snapshot primitives for checkpoint `base_snapshot` and `target_snapshot`.
- Provide command guard and safety scanner hooks inspired by Hermes without depending on Hermes.

Acceptance criteria:

- No paper-run-scoped command template invokes Codex, Claude, or any provider CLI directly.
- Every decomposer, planner, synthesizer, and reviewer output has a corresponding `agent-run` record.
- Parent checkpoint reviewers have distinct `run_id` values and separate output artifacts.
- `independence_group` validation rejects duplicated reviewer outputs counted as two independent reviews.
- Read-only roles cannot write to the reproduction workspace.
- Worker roles cannot write outside the configured reproduction workspace.
- Snapshot records can be linked from checkpoint `base_snapshot` and `target_snapshot`.
- Runtime adapter tests use mocks and do not require Hermes, Codex, Claude, or network access.

### 8.3 Paper ingestion, extraction, and decomposition

Create:

- `scripts/validate-paper-repro-plan-io.sh`
- `scripts/paper-input-sanitize.sh`
- `scripts/paper-extract.sh`
- `scripts/paper-classify.sh`
- `scripts/paper-evidence-map.sh`
- `scripts/paper-decompose.sh`
- `agents/paper-type-classifier.md`
- `agents/paper-evidence-extractor.md`
- `agents/paper-decomposer.md`
- `prompt-template/paper/`

Responsibilities:

- Convert input into normalized text where possible.
- Preserve page, section, figure, table, equation, algorithm, and appendix references.
- Classify paper type with confidence and mixed-type support.
- Extract claims, methods, experiments, and ambiguities as evidence records.
- Decompose paper modules before implementation planning.
- Defer final criteria generation until evidence records have been bound to paper modules.

Acceptance criteria:

- A non-ML systems paper does not receive ML-only required artifacts.
- An inference optimization paper receives benchmark/profiling/hardware artifacts and marks training as not applicable unless the paper includes training claims.
- Evidence records include source references or are marked as assumptions.
- Paper decomposition outputs enough module lineage for downstream criteria generation.

### 8.4 Multi-agent plan generation

Create:

- `commands/gen-paper-repro-plan.md`
- `skills/humanize-gen-paper-repro-plan/SKILL.md`
- `agents/paper-repro-planner-a.md`
- `agents/paper-repro-planner-b.md`
- `agents/paper-repro-synthesizer.md`
- `agents/checkpoint-planner.md`
- `prompt-template/paper/gen-paper-repro-plan-template.md`

Responsibilities:

- Generate independent implementation plans after evidence extraction and paper decomposition.
- Generate reproduction criteria from the evidence map plus paper decomposition, not from raw extraction alone.
- Launch Planner A, Planner B, Synthesizer, and checkpoint planner through `agent-runner`.
- Synthesize plans.
- Return to independent planners for review.
- Produce final `paper-repro-plan.md` and `paper-repro-plan.json`.

Acceptance criteria:

- The final plan records both independent plans, synthesis decisions, unresolved disagreements, and final review notes.
- The plan includes parent and child checkpoints with explicit reviewer counts.
- Every implementation task has valid `lineage_mode`, non-empty `module_ids`, non-empty `criterion_ids`, and `checkpoint_id`.
- Tasks with `lineage_mode` of `single` or `primary` have `primary_module_id` and `primary_criterion_id`; tasks with `multi_equal` omit primary lineage fields.
- Every criterion belongs to at least one module.
- Planner A, Planner B, Synthesizer, and checkpoint planner runs are recorded in `agent_runs`.
- The plan JSON can be passed directly to `start-paper-repro-loop`.

### 8.5 Checkpoint loop engine

Create:

- `scripts/setup-paper-repro-loop.sh`
- `hooks/loop-paper-repro-stop-hook.sh`
- `scripts/paper-repro-status.sh`
- `scripts/checkpoint-validate.sh`
- `prompt-template/paper/checkpoint-review.md`
- `prompt-template/paper/parent-checkpoint-review.md`
- `prompt-template/paper/next-checkpoint-prompt.md`

Responsibilities:

- Track current checkpoint instead of round number.
- Require expected artifacts before review.
- Run one reviewer for child checkpoints through `agent-runner`.
- Run two independent reviewers for parent checkpoints through `agent-runner`.
- Record reviewer run IDs so the same output cannot count twice.
- Merge reviewer feedback without silently discarding disagreements.
- Block progression if reasonable reviewer findings remain unresolved.

Acceptance criteria:

- A child checkpoint cannot pass without one reviewer verdict.
- A parent checkpoint cannot pass without two independent reviewer verdicts.
- Parent checkpoint verdicts must have different reviewer run IDs.
- Parent checkpoint reviewer runs must share an `independence_group` and have distinct `run_id` values.
- Parent checkpoint reviewer verdicts must reference separate `summary_artifact` or `output_artifacts`.
- If both parent reviewers raise reasonable non-conflicting findings, both are carried into the next work prompt.
- If reviewers conflict, the worker receives an explicit arbitration task.

### 8.6 Type-aware reproduction package generation

Create:

- `prompt-template/paper/reproduction-report.md`
- `templates/reproduce.sh`
- `templates/reproduction-report.md`
- `scripts/repro-package-audit.sh`
- `scripts/result-compare.sh`

Responsibilities:

- Ensure every finished workspace has an executable top-level workflow.
- Compare reproduced outputs to paper claims with tolerances.
- Generate `results.json`.
- Generate a final report that distinguishes reproduced, partially reproduced, failed, blocked, and not-applicable items.

Acceptance criteria:

- ML papers with training claims include training artifacts.
- Inference optimization papers do not require training artifacts unless evidence requires them.
- Result comparison supports exact match, tolerance match, trend match, qualitative/structural match, missing output, and unit mismatch.
- The final report maps results back to module IDs, criteria, checkpoints, and paper evidence.

### 8.7 Artifact and git policy

Paper loops need a different artifact policy from RLCR.

Rules:

- Source files, environment files, plan files, `reproduce.sh`, `results.json`, and final reports are deliverables.
- Large generated outputs should live under workspace `outputs/` and follow a configured commit/ignore policy.
- Checkpoint review evidence should reference large artifacts by path, hash, and summary instead of embedding them in prompts.
- Large-file checks should distinguish source, report, runtime state, and generated artifact output.
- Git-clean gates should understand the paper workspace policy.

### 8.8 Governance and safety

Create:

- `scripts/skill-safety-audit.sh`
- `scripts/memory-safety-audit.sh`
- `scripts/paper-input-safety-audit.sh`
- `agents/skill-safety-reviewer.md`
- `agents/memory-safety-reviewer.md`
- `agents/paper-input-safety-reviewer.md`

Rules:

- Do not store secrets in memory.
- Do not store copyrighted paper text beyond short evidence references and summaries.
- Do not promote skills that modify protected loop state, credentials, global shell config, or git history.
- Require human approval for skills that run network, install packages globally, or affect credentials.
- Treat paper input and supplementary archives as untrusted data.

Acceptance criteria:

- Safety audit fails candidate skills containing credential access, destructive git commands, global config writes, encoded destructive payloads, or broad shell execution without safeguards.
- Memory audit redacts secrets before writing.
- Paper input audit blocks prompt-injection directives from becoming agent instructions.

## 9. Testing Plan

Add test suites:

- `tests/test-provider-role-routing.sh`
- `tests/test-agent-runner.sh`
- `tests/test-runtime-adapter-layer.sh`
- `tests/test-agent-run-independence.sh`
- `tests/test-snapshot-manager.sh`
- `tests/test-paper-prompt-injection.sh`
- `tests/test-paper-input-privacy.sh`
- `tests/test-paper-type-classification.sh`
- `tests/test-paper-decomposition.sh`
- `tests/test-artifact-profile.sh`
- `tests/test-paper-repro-plan.sh`
- `tests/test-checkpoint-graph.sh`
- `tests/test-paper-repro-loop.sh`
- `tests/test-parent-child-review.sh`
- `tests/test-reproduce-entrypoint-contract.sh`
- `tests/test-result-compare-tolerances.sh`
- `tests/test-checkpoint-state-migration.sh`
- `tests/test-memory-lifecycle.sh`
- `tests/test-skill-lifecycle.sh`
- `tests/test-skill-safety.sh`

Fixtures:

- ML training paper excerpt.
- Inference optimization paper excerpt.
- Systems benchmark paper excerpt.
- Numerical simulation paper excerpt.
- Data analysis paper excerpt.
- Algorithm experiment paper excerpt.
- Mixed ML plus systems optimization excerpt.
- Mixed simulation plus data analysis excerpt.
- Ambiguous paper excerpt with missing method details.
- Prompt-injection PDF/text fixture.
- Small PDF, LaTeX, and Markdown fixtures with no network dependency.

Critical negative tests:

- ML-only artifacts are not required for non-ML papers.
- Training is not required for an inference-only paper.
- Criteria without module lineage are rejected.
- Checkpoints without module coverage are rejected.
- Implementation tasks without valid `lineage_mode`, non-empty `module_ids`, non-empty `criterion_ids`, and `checkpoint_id` are rejected.
- Implementation tasks with `lineage_mode` of `single` or `primary` but missing `primary_module_id` or `primary_criterion_id` are rejected.
- Implementation tasks with `lineage_mode` of `single` and more than one module or criterion are rejected.
- Implementation tasks with `lineage_mode` of `single` and primary IDs that do not equal the unique module and criterion IDs are rejected.
- Implementation tasks with `lineage_mode` of `primary` and primary IDs missing from the corresponding arrays are rejected.
- Implementation tasks with `lineage_mode` of `multi_equal` and populated primary lineage fields are rejected.
- Parent checkpoint with only one reviewer cannot pass.
- Parent checkpoint with duplicated reviewer run ID cannot pass.
- Parent checkpoint with duplicated reviewer output artifacts cannot pass.
- Paper-run-scoped agents launched outside `agent-runner` are rejected by command/template validation.
- Read-only runtime roles cannot write to the reproduction workspace.
- Worker runtime roles cannot write outside the reproduction workspace.
- Reviewer disagreement cannot be dropped silently.
- Provider role swap does not require Codex when Claude is the configured reviewer.
- Result comparison handles exact, numeric tolerance, trend, qualitative/structural, missing output, and unit mismatch.
- Memory redaction occurs before write.
- Skill safety catches shell redirection, destructive git commands, credential paths, global config writes, network installs, and encoded payloads.

## 10. Migration Strategy

Phase 1: Schemas and dry-run paper planning.

- Add schema files.
- Add `paper-repro-plan.json` manifest.
- Add fixture-driven extraction, decomposition, criteria, artifact profile, and checkpoint graph tests.
- Do not start implementation.

Phase 2: Provider abstraction without behavior change.

- Preserve current `/humanize:start-rlcr-loop` defaults.
- Introduce provider adapter tests.
- Keep existing Codex path as the default adapter.
- Make dependency checks role-aware.

Phase 3: Runtime adapter and agent-runner MVP.

- Add `agent-run.schema.json` and `runtime-adapter.schema.json`.
- Add `agent-runner` with mocked provider execution.
- Add runtime adapter validation for role, provider, workspace, write, network, timeout, input artifact, output artifact, and redaction fields.
- Add snapshot-manager interfaces for `base_snapshot` and `target_snapshot`.
- Reject paper-run-scoped provider invocations that bypass `agent-runner`.
- Keep Hermes as a design reference only; do not add a Hermes dependency in this phase.

Phase 4: Paper reproduction planning command.

- Add `gen-paper-repro-plan`.
- Generate both Markdown and JSON.
- Add workspace contract and from-scratch policy.
- Record decomposer, planner, synthesizer, and checkpoint planner executions in `agent_runs`.

Phase 5: Independent paper checkpoint loop.

- Add `setup-paper-repro-loop.sh`.
- Add `loop-paper-repro-stop-hook.sh`.
- Use checkpoint files instead of round files.
- Validate child/parent gates with mock reviewers.
- Launch checkpoint reviewers through `agent-runner`.

Phase 6: Final package audit.

- Add `reproduce.sh` template and contract tests.
- Add `results.json` generation and comparison.
- Add reproduction report mapping back to modules, criteria, checkpoints, and evidence.

Phase 7: Minimal memory.

- Capture redacted event records.
- Redact before write.
- Add memory selection only after dry-run and checkpoint loop are stable.

Phase 8: Skill candidates.

- Generate candidate skills from validated procedural memory.
- Keep candidates under `.humanize/skills/candidates/` by default.
- Add validation, promotion, selection, and deprecation.

Phase 9: Optional Hermes adapter evaluation.

- Evaluate whether Humanize's shell/hook runtime has become a bottleneck.
- Consider `hermes-paper-repro-adapter` only after `paper-repro-core` contracts and Humanize paper loop behavior are stable.
- Do not move paper reproduction semantics into Hermes; Hermes remains an optional runtime adapter.

Phase 10: Documentation and release.

- Update README, usage docs, install docs, config docs, and version metadata.
- Add examples for ML, inference optimization, systems, numerical simulation, and data analysis papers.

## 11. Configuration Additions

Add defaults to `config/default_config.json`:

```json
{
  "worker_provider": "claude",
  "worker_model": "default",
  "worker_effort": "medium",
  "worker_timeout_seconds": 3600,
  "worker_sandbox_mode": "workspace-write",
  "worker_write_policy": "workspace-only",
  "worker_network_policy": "budget-controlled",

  "summary_reviewer_provider": "codex",
  "summary_reviewer_model": "default",
  "summary_reviewer_effort": "high",
  "summary_reviewer_timeout_seconds": 1800,
  "summary_reviewer_sandbox_mode": "read-only",
  "summary_reviewer_write_policy": "none",
  "summary_reviewer_network_policy": "disabled",

  "code_reviewer_provider": "codex",
  "code_reviewer_model": "default",
  "code_reviewer_effort": "high",
  "code_reviewer_timeout_seconds": 1800,
  "code_reviewer_sandbox_mode": "read-only",
  "code_reviewer_write_policy": "none",
  "code_reviewer_network_policy": "disabled",

  "planner_strategy": "mixed",
  "planner_provider": "codex",
  "planner_a_provider": "codex",
  "planner_a_model": "default",
  "planner_a_effort": "high",
  "planner_a_timeout_seconds": 3600,
  "planner_a_sandbox_mode": "read-only",
  "planner_a_write_policy": "none",
  "planner_a_network_policy": "disabled",
  "planner_b_provider": "claude",
  "planner_b_model": "default",
  "planner_b_effort": "high",
  "planner_b_timeout_seconds": 3600,
  "planner_b_sandbox_mode": "read-only",
  "planner_b_write_policy": "none",
  "planner_b_network_policy": "disabled",
  "planner_synthesizer_provider": "codex",
  "planner_synthesizer_model": "default",
  "planner_synthesizer_effort": "high",
  "planner_synthesizer_timeout_seconds": 3600,
  "planner_synthesizer_sandbox_mode": "read-only",
  "planner_synthesizer_write_policy": "none",
  "planner_synthesizer_network_policy": "disabled",

  "memory_provider": "codex",
  "memory_model": "default",
  "memory_effort": "medium",
  "memory_timeout_seconds": 1200,
  "memory_sandbox_mode": "read-only",
  "memory_write_policy": "redacted-memory-only",
  "memory_network_policy": "disabled",

  "skill_provider": "codex",
  "skill_model": "default",
  "skill_effort": "high",
  "skill_timeout_seconds": 1800,
  "skill_sandbox_mode": "read-only",
  "skill_write_policy": "candidate-only",
  "skill_network_policy": "disabled",

  "runtime_adapter": "humanize",
  "runtime_adapter_allow_hermes": false,
  "runtime_agent_runner_required": true,
  "runtime_default_tool_policy": "role-scoped",
  "runtime_snapshot_manager": "shadow-git-compatible",
  "runtime_command_guard": true,
  "runtime_terminal_backend": "local",

  "paper_repro_budget": "standard",
  "paper_repro_workspace_root": "paper-repro",
  "paper_repro_from_scratch_policy": "pure",
  "paper_repro_enable_memory": false,
  "paper_repro_enable_skill_candidates": false,
  "paper_repro_auto_promote_skills": false,
  "paper_repro_require_human_approval_for_risky_skills": true,
  "paper_repro_default_child_reviewers": 1,
  "paper_repro_default_parent_reviewers": 2,
  "paper_repro_pdf_remote_parsing": false
}
```

Memory and skill candidate generation default to false for MVP stability. They can be enabled after checkpoint-loop and final-package behavior is reliable.

## 12. Documentation Plan

Create:

- `docs/paper-reproduction.md`
- `docs/provider-roles.md`
- `docs/runtime-adapter-layer.md`
- `docs/paper-repro-core.md`
- `docs/checkpoint-reviews.md`
- `docs/memory-and-skills.md`
- `docs/paper-artifact-profiles.md`
- `docs/paper-decomposition.md`
- `docs/paper-workspace-contract.md`
- `docs/examples/paper-repro-ml.md`
- `docs/examples/paper-repro-inference-optimization.md`
- `docs/examples/paper-repro-systems.md`
- `docs/examples/paper-repro-numerical-simulation.md`
- `docs/examples/paper-repro-data-analysis.md`

Documentation must include:

- How to choose or override a paper type.
- How paper decomposition works.
- How module/criterion/checkpoint lineage works.
- How artifact profiles differ by paper type.
- How parent and child checkpoints work.
- How reviewer disagreement is handled.
- How the workspace is created and audited.
- Why Humanize remains the MVP runner and Hermes is an optional future adapter.
- How `paper-repro-core`, `humanize-paper-runner`, and runtime adapters split responsibilities.
- Why paper-run-scoped agents must be launched through `agent-runner`.
- How `reproduce.sh` and `results.json` must behave.
- How memory is stored, updated, and audited.
- How candidate skills are generated, validated, and promoted.
- How to disable memory or skill evolution for privacy-sensitive projects.

## 13. Open Design Decisions for Human Review

These decisions should be resolved before implementation:

- Whether paper loop should use a universal stop-hook dispatcher immediately or first ship a dedicated `loop-paper-repro-stop-hook.sh`.
- Whether generated project-local skills should ever be promoted automatically into `.claude/skills/`, or always require human approval.
- Whether paper PDFs should be parsed locally only, or whether optional remote conversion services are allowed.
- Whether final reproduction reports should be mandatory for smoke-only reproductions.
- Whether parent checkpoint reviewers must use different providers or only different run IDs.
- Whether memory and skill evolution should stay disabled by default until a project opts in.
- Whether existing official or third-party code should be allowed in `reference-only` mode by default.
- When, if ever, to build a Hermes adapter after the Humanize runner is stable.

## 14. Reference Index

- PaperBench: hierarchical rubrics for from-scratch paper replication by agents. https://openai.com/index/paperbench/
- RePro: paper fingerprint and fine-grained verification/refinement loop. https://arxiv.org/abs/2508.16671
- Paper2Code/PaperCoder: planning, analysis, generation, specialized agents, dependency-aware code generation. https://arxiv.org/abs/2504.17192
- ACM Artifact Review and Badging: artifact and result validation categories. https://www.acm.org/publications/policies/artifact-review-and-badging-current
- ECRTS Artifact Evaluation: figure/table-linked repeatability documents and platform dependency reporting. https://archives.ecrts.org/fileadmin/WebsitesArchiv/ecrts2025/artifact-evaluation/
- Kempner Institute reproducible research handbook: pinned dependencies, isolated environments, data/config versioning, full pipeline instructions, output metadata. https://handbook.eng.kempnerinstitute.harvard.edu/s2_swe_for_research/reproducible_research.html
- Nature computational reproducibility guidelines: validation expectations differ for custom code, available software, simulations, and ML/data-driven work. https://www.nature.com/documents/Computational_tools_reporting_guidelines.pdf
- Ten Simple Rules for Reproducible Computational Research: executable workflows and versioned code states. https://pmc.ncbi.nlm.nih.gov/articles/PMC3812051/
- Reflexion: verbal reflection and episodic memory for trial-to-trial improvement. https://arxiv.org/abs/2303.11366
- Generative Agents: observation, planning, and reflection architecture. https://arxiv.org/abs/2304.03442
- Voyager: automatic curriculum, executable skill library, feedback-driven skill improvement. https://arxiv.org/abs/2305.16291
- A-MEM: dynamic memory organization, linking, and memory evolution. https://arxiv.org/abs/2502.12110
- Letta/MemGPT memory architecture: stateful agents with memory hierarchy and memory blocks. https://docs.letta.com/guides/agents/architectures/memgpt
- Claude Code skills: `SKILL.md` packages, supporting files, project/plugin skills, dynamic context. https://code.claude.com/docs/en/skills
- SkillX: automated multi-level skill knowledge bases with refinement and expansion. https://arxiv.org/abs/2604.04804
- CoEvoSkills: self-evolving multi-file skill packages with generator/verifier co-evolution. https://arxiv.org/abs/2604.01687
- SKILL.md supply-chain risk: semantic attacks across discovery, selection, and governance. https://arxiv.org/abs/2605.11418
